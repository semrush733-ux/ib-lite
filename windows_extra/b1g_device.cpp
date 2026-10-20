// Windows side of the app's "b1g/device" channel (the Android side is MainActivity.kt).
// Copied into windows/runner/ by tools/windows_setup.py; see b1g_device.h.
//
//   deviceIds        machine id (the app sends only a hash of it) and the network cards' MAC
//   deviceInfo       maker, model, Windows version, memory, screen (for "Report a problem")
//   deviceClass      memory and processor cores (Picture Enhance starts at what the PC carries)
//   netInfo          cable / Wi-Fi, network name, signal, IP address, speed (Settings > Network)
//   wifiScan         Wi-Fi networks nearby; wifiJoin / wifiSettings open the Windows Wi-Fi page
//   wifiPermission   newer Windows wants location access for the Wi-Fi list: opens that page
//   openUrl          web pages (film trailers) in the default browser
//   keepScreenOn     no screen saver or sleep while a video plays
//   toggleFullScreen / setFullScreen / isFullScreen   F11, Alt+Enter
#pragma warning(push, 0)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <wlanapi.h>
#include <shellapi.h>
#pragma warning(pop)

#include "b1g_device.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <thread>
#include <variant>
#include <vector>

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "wlanapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")

namespace b1g_device {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;
HWND g_window = nullptr;
bool g_full = false;
LONG_PTR g_style = 0;
WINDOWPLACEMENT g_place{};

std::string Utf8(const std::wstring& text) {
  if (text.empty()) return std::string();
  const int count = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0,
                                        nullptr, nullptr);
  if (count <= 0) return std::string();
  std::string out(static_cast<size_t>(count), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), count, nullptr,
                      nullptr);
  return out;
}

std::wstring Wide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int count = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), count);
  return out;
}

std::string RegString(const wchar_t* key, const wchar_t* name) {
  wchar_t buffer[512] = {0};
  DWORD size = static_cast<DWORD>(sizeof(buffer));
  if (RegGetValueW(HKEY_LOCAL_MACHINE, key, name, RRF_RT_REG_SZ, nullptr, buffer, &size) != ERROR_SUCCESS) {
    return std::string();
  }
  return Utf8(std::wstring(buffer));
}

// The network cards (with gateways when asked). Empty when Windows does not answer.
std::vector<unsigned char> Adapters(ULONG flags) {
  ULONG size = 16 * 1024;
  std::vector<unsigned char> buffer(size);
  for (int attempt = 0; attempt < 3; attempt++) {
    const ULONG code = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr,
                                            reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data()), &size);
    if (code == NO_ERROR) return buffer;
    if (code != ERROR_BUFFER_OVERFLOW) break;
    buffer.resize(size);
  }
  return std::vector<unsigned char>();
}

// VPNs, virtual machines and similar: never used as this computer's identity or connection.
bool IsVirtual(const IP_ADAPTER_ADDRESSES* adapter) {
  const std::wstring description = adapter->Description != nullptr ? adapter->Description : L"";
  const wchar_t* words[] = {L"Virtual", L"VMware",    L"VirtualBox", L"Hyper-V",  L"TAP-",
                            L"WireGuard", L"VPN",     L"Loopback",   L"Bluetooth", L"WAN Miniport"};
  for (const wchar_t* word : words) {
    if (description.find(word) != std::wstring::npos) return true;
  }
  return false;
}

// Real network cards first (cable, then Wi-Fi).
EncodableList Macs() {
  EncodableList out;
  std::vector<unsigned char> buffer =
      Adapters(GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER);
  if (buffer.empty()) return out;
  for (int pass = 0; pass < 2; pass++) {
    const ULONG wanted = pass == 0 ? IF_TYPE_ETHERNET_CSMACD : IF_TYPE_IEEE80211;
    for (auto adapter = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data()); adapter != nullptr;
         adapter = adapter->Next) {
      if (adapter->PhysicalAddressLength != 6 || adapter->IfType != wanted || IsVirtual(adapter)) continue;
      const BYTE* p = adapter->PhysicalAddress;
      char mac[32] = {0};
      snprintf(mac, sizeof(mac), "%02X:%02X:%02X:%02X:%02X:%02X", static_cast<unsigned>(p[0]),
               static_cast<unsigned>(p[1]), static_cast<unsigned>(p[2]), static_cast<unsigned>(p[3]),
               static_cast<unsigned>(p[4]), static_cast<unsigned>(p[5]));
      out.push_back(EncodableValue(std::string(mac)));
    }
  }
  return out;
}

void AddMemory(EncodableMap& out) {
  MEMORYSTATUSEX memory{};
  memory.dwLength = static_cast<DWORD>(sizeof(memory));
  if (GlobalMemoryStatusEx(&memory)) {
    out[EncodableValue("ramMb")] = EncodableValue(static_cast<int64_t>(memory.ullTotalPhys / (1024 * 1024)));
    out[EncodableValue("freeRamMb")] = EncodableValue(static_cast<int64_t>(memory.ullAvailPhys / (1024 * 1024)));
  }
  out[EncodableValue("cores")] = EncodableValue(static_cast<int>(std::thread::hardware_concurrency()));
  out[EncodableValue("lowRam")] = EncodableValue(false);
}

EncodableMap DeviceInfo() {
  EncodableMap out;
  const wchar_t* bios = L"HARDWARE\\DESCRIPTION\\System\\BIOS";
  const wchar_t* nt = L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";
  out[EncodableValue("manufacturer")] = EncodableValue(RegString(bios, L"SystemManufacturer"));
  out[EncodableValue("model")] = EncodableValue(RegString(bios, L"SystemProductName"));
  const std::string build = RegString(nt, L"CurrentBuildNumber");
  const std::string release = RegString(nt, L"DisplayVersion");
  std::string windows = std::atoi(build.c_str()) >= 22000 ? "Windows 11" : "Windows 10";
  if (!release.empty()) windows += " " + release;
  out[EncodableValue("windows")] = EncodableValue(windows);
  out[EncodableValue("build")] = EncodableValue(build);
  out[EncodableValue("abi")] = EncodableValue(std::string("x64"));
  AddMemory(out);
  const UINT dpi = g_window != nullptr ? GetDpiForWindow(g_window) : 96;
  out[EncodableValue("screen")] = EncodableValue(std::to_string(GetSystemMetrics(SM_CXSCREEN)) + "x" +
                                                 std::to_string(GetSystemMetrics(SM_CYSCREEN)) + " @" +
                                                 std::to_string(dpi) + "dpi");
  return out;
}

// Signal quality (0..100) as the app's 0..4 bars.
int Bars(ULONG quality) {
  if (quality >= 80) return 4;
  if (quality >= 60) return 3;
  if (quality >= 40) return 2;
  if (quality >= 20) return 1;
  return 0;
}

int ChannelMhz(ULONG channel) {
  if (channel == 0) return 0;
  if (channel <= 13) return static_cast<int>(2407 + 5 * channel);
  if (channel == 14) return 2484;
  return static_cast<int>(5000 + 5 * channel);
}

class WlanClient {
 public:
  WlanClient() {
    DWORD version = 0;
    if (WlanOpenHandle(2, nullptr, &version, &handle_) != ERROR_SUCCESS) handle_ = nullptr;
  }
  ~WlanClient() {
    if (handle_ != nullptr) WlanCloseHandle(handle_, nullptr);
  }
  WlanClient(const WlanClient&) = delete;
  WlanClient& operator=(const WlanClient&) = delete;
  HANDLE handle() const { return handle_; }

 private:
  HANDLE handle_ = nullptr;
};

EncodableMap NetInfo() {
  std::string type = "none";
  std::string ip;
  int64_t mbps = 0;
  std::vector<unsigned char> buffer = Adapters(GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_SKIP_ANYCAST |
                                               GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER);
  if (!buffer.empty()) {
    for (auto adapter = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data()); adapter != nullptr;
         adapter = adapter->Next) {
      if (adapter->OperStatus != IfOperStatusUp || adapter->FirstGatewayAddress == nullptr || IsVirtual(adapter)) {
        continue;
      }
      std::string address;
      for (auto unicast = adapter->FirstUnicastAddress; unicast != nullptr; unicast = unicast->Next) {
        const SOCKADDR* socket_address = unicast->Address.lpSockaddr;
        if (socket_address == nullptr || socket_address->sa_family != AF_INET) continue;
        char text[INET_ADDRSTRLEN] = {0};
        const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(socket_address);
        if (inet_ntop(AF_INET, &ipv4->sin_addr, text, sizeof(text)) != nullptr) {
          address = text;
          break;
        }
      }
      if (address.empty()) continue;
      ip = address;
      type = adapter->IfType == IF_TYPE_IEEE80211 ? "wifi"
                                                   : (adapter->IfType == IF_TYPE_ETHERNET_CSMACD ? "ethernet" : "other");
      mbps = static_cast<int64_t>(adapter->TransmitLinkSpeed / 1000000ULL);
      break;
    }
  }

  bool wifi_on = false;
  std::string ssid;
  int level = 0;
  int frequency = 0;
  WlanClient wlan;
  if (wlan.handle() != nullptr) {
    PWLAN_INTERFACE_INFO_LIST interfaces = nullptr;
    if (WlanEnumInterfaces(wlan.handle(), nullptr, &interfaces) == ERROR_SUCCESS && interfaces != nullptr) {
      for (DWORD i = 0; i < interfaces->dwNumberOfItems; i++) {
        const WLAN_INTERFACE_INFO& info = interfaces->InterfaceInfo[i];
        wifi_on = true;
        if (info.isState != wlan_interface_state_connected) continue;
        DWORD size = 0;
        WLAN_OPCODE_VALUE_TYPE value_type = wlan_opcode_value_type_invalid;
        PWLAN_CONNECTION_ATTRIBUTES connection = nullptr;
        if (WlanQueryInterface(wlan.handle(), &info.InterfaceGuid, wlan_intf_opcode_current_connection, nullptr,
                               &size, reinterpret_cast<PVOID*>(&connection), &value_type) == ERROR_SUCCESS &&
            connection != nullptr) {
          const DOT11_SSID& name = connection->wlanAssociationAttributes.dot11Ssid;
          ssid.assign(reinterpret_cast<const char*>(name.ucSSID), static_cast<size_t>(name.uSSIDLength));
          level = Bars(connection->wlanAssociationAttributes.wlanSignalQuality);
          WlanFreeMemory(connection);
        }
        PULONG channel = nullptr;
        size = 0;
        if (WlanQueryInterface(wlan.handle(), &info.InterfaceGuid, wlan_intf_opcode_channel_number, nullptr, &size,
                               reinterpret_cast<PVOID*>(&channel), &value_type) == ERROR_SUCCESS &&
            channel != nullptr) {
          frequency = ChannelMhz(*channel);
          WlanFreeMemory(channel);
        }
        break;
      }
      WlanFreeMemory(interfaces);
    }
  }

  EncodableMap out;
  out[EncodableValue("type")] = EncodableValue(type);
  out[EncodableValue("ssid")] = EncodableValue(type == "wifi" ? ssid : std::string());
  out[EncodableValue("level")] = EncodableValue(type == "wifi" ? level : 0);
  out[EncodableValue("ip")] = EncodableValue(ip);
  out[EncodableValue("linkMbps")] = EncodableValue(mbps);
  out[EncodableValue("frequency")] = EncodableValue(type == "wifi" ? frequency : 0);
  out[EncodableValue("canJoin")] = EncodableValue(false);
  out[EncodableValue("location")] = EncodableValue(true);
  out[EncodableValue("wifiOn")] = EncodableValue(wifi_on);
  return out;
}

EncodableMap WifiScan() {
  EncodableList networks;
  std::vector<std::string> seen;
  bool permission = true;
  WlanClient wlan;
  if (wlan.handle() != nullptr) {
    PWLAN_INTERFACE_INFO_LIST interfaces = nullptr;
    if (WlanEnumInterfaces(wlan.handle(), nullptr, &interfaces) == ERROR_SUCCESS && interfaces != nullptr) {
      for (DWORD i = 0; i < interfaces->dwNumberOfItems; i++) {
        const GUID& id = interfaces->InterfaceInfo[i].InterfaceGuid;
        WlanScan(wlan.handle(), &id, nullptr, nullptr, nullptr);
        PWLAN_AVAILABLE_NETWORK_LIST available = nullptr;
        const DWORD code = WlanGetAvailableNetworkList(wlan.handle(), &id, 0, nullptr, &available);
        if (code == ERROR_ACCESS_DENIED) {
          permission = false;
          continue;
        }
        if (code != ERROR_SUCCESS || available == nullptr) continue;
        for (DWORD k = 0; k < available->dwNumberOfItems; k++) {
          const WLAN_AVAILABLE_NETWORK& network = available->Network[k];
          if (network.dot11Ssid.uSSIDLength == 0) continue;
          const std::string name(reinterpret_cast<const char*>(network.dot11Ssid.ucSSID),
                                 static_cast<size_t>(network.dot11Ssid.uSSIDLength));
          bool duplicate = false;
          for (const std::string& other : seen) {
            if (other == name) {
              duplicate = true;
              break;
            }
          }
          if (duplicate) continue;
          seen.push_back(name);
          EncodableMap entry;
          entry[EncodableValue("ssid")] = EncodableValue(name);
          entry[EncodableValue("level")] = EncodableValue(Bars(network.wlanSignalQuality));
          entry[EncodableValue("secured")] = EncodableValue(network.bSecurityEnabled != FALSE);
          entry[EncodableValue("band")] = EncodableValue(std::string());
          networks.push_back(EncodableValue(entry));
        }
        WlanFreeMemory(available);
      }
      WlanFreeMemory(interfaces);
    }
  }
  EncodableMap out;
  out[EncodableValue("permission")] = EncodableValue(permission);
  out[EncodableValue("list")] = EncodableValue(networks);
  return out;
}

// Only web pages and the Windows settings pages, never files or programs.
bool Open(const std::string& url) {
  if (url.rfind("https://", 0) != 0 && url.rfind("http://", 0) != 0 && url.rfind("ms-settings:", 0) != 0) {
    return false;
  }
  const std::wstring target = Wide(url);
  const HINSTANCE code = ShellExecuteW(nullptr, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(code) > 32;
}

void SetFullScreen(bool on) {
  if (g_window == nullptr || on == g_full) return;
  if (on) {
    g_style = GetWindowLongPtrW(g_window, GWL_STYLE);
    g_place.length = static_cast<UINT>(sizeof(WINDOWPLACEMENT));
    GetWindowPlacement(g_window, &g_place);
    MONITORINFO monitor{};
    monitor.cbSize = static_cast<DWORD>(sizeof(monitor));
    GetMonitorInfoW(MonitorFromWindow(g_window, MONITOR_DEFAULTTONEAREST), &monitor);
    SetWindowLongPtrW(g_window, GWL_STYLE, g_style & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW));
    SetWindowPos(g_window, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
                 monitor.rcMonitor.right - monitor.rcMonitor.left, monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    SetWindowLongPtrW(g_window, GWL_STYLE, g_style);
    SetWindowPlacement(g_window, &g_place);
    SetWindowPos(g_window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  g_full = on;
}

void Handle(const flutter::MethodCall<EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableValue* args = call.arguments();
  if (method == "deviceIds") {
    EncodableMap out;
    const std::string machine = RegString(L"SOFTWARE\\Microsoft\\Cryptography", L"MachineGuid");
    if (!machine.empty()) out[EncodableValue("hwid")] = EncodableValue(machine);
    out[EncodableValue("macs")] = EncodableValue(Macs());
    result->Success(EncodableValue(out));
  } else if (method == "deviceInfo") {
    result->Success(EncodableValue(DeviceInfo()));
  } else if (method == "deviceClass") {
    EncodableMap out;
    AddMemory(out);
    result->Success(EncodableValue(out));
  } else if (method == "openUrl") {
    const std::string* url = args != nullptr ? std::get_if<std::string>(args) : nullptr;
    result->Success(EncodableValue(url != nullptr && Open(*url)));
  } else if (method == "keepScreenOn") {
    const bool* on = args != nullptr ? std::get_if<bool>(args) : nullptr;
    SetThreadExecutionState(on != nullptr && *on ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED)
                                                 : ES_CONTINUOUS);
    result->Success();
  } else if (method == "toggleFullScreen") {
    SetFullScreen(!g_full);
    result->Success(EncodableValue(g_full));
  } else if (method == "setFullScreen") {
    const bool* on = args != nullptr ? std::get_if<bool>(args) : nullptr;
    SetFullScreen(on != nullptr ? *on : !g_full);
    result->Success(EncodableValue(g_full));
  } else if (method == "isFullScreen") {
    result->Success(EncodableValue(g_full));
  } else if (method == "netInfo") {
    result->Success(EncodableValue(NetInfo()));
  } else if (method == "wifiScan") {
    result->Success(EncodableValue(WifiScan()));
  } else if (method == "wifiPermission") {
    Open("ms-settings:privacy-location");
    result->Success();
  } else if (method == "wifiJoin") {
    Open("ms-settings:network-wifi");
    result->Success(EncodableValue(std::string("settings")));
  } else if (method == "wifiSettings") {
    Open("ms-settings:network-wifi");
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void Register(flutter::BinaryMessenger* messenger, HWND window) {
  g_window = window;
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "b1g/device", &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(Handle);
}

}  // namespace b1g_device
