package com.liteplayer.recorder

import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class ApiError(val status: Int, message: String, val body: JSONObject = JSONObject()) : IOException(message)

/**
 * Talks to the website plugin (Lite Recorder Cloud). Uses ?rest_route= so it works on every
 * WordPress, with or without pretty links.
 */
class Net(private val site: String, private val token: String = "") {

    private fun url(route: String, query: Map<String, String> = emptyMap()): URL {
        val q = StringBuilder("rest_route=").append(enc("/lrc/v1/$route"))
        query.forEach { (k, v) -> q.append('&').append(enc(k)).append('=').append(enc(v)) }
        val base = site.trimEnd('/')
        return URL("$base/?$q")
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    private fun open(u: URL, method: String): HttpURLConnection {
        val c = u.openConnection() as HttpURLConnection
        c.requestMethod = method
        c.connectTimeout = 15000
        c.readTimeout = 60000
        c.instanceFollowRedirects = true
        c.setRequestProperty("Accept", "application/json")
        c.setRequestProperty("User-Agent", "LiteRecorder/${BuildConfig.VERSION_NAME} (Android)")
        if (token.isNotEmpty()) c.setRequestProperty("X-LRC-Token", token)
        return c
    }

    private fun read(c: HttpURLConnection): JSONObject {
        val code = c.responseCode
        val text = try {
            (if (code >= 400) c.errorStream else c.inputStream)?.bufferedReader()?.use { it.readText() } ?: ""
        } finally {
            c.disconnect()
        }
        val json = try {
            JSONObject(text.substring(maxOf(0, text.indexOf('{'))))
        } catch (_: Exception) {
            JSONObject()
        }
        if (code >= 400) {
            val msg = json.optString("message").ifEmpty {
                if (code == 404) "The website does not have the Lite Recorder Cloud plugin (or the address is wrong)."
                else "Website error $code"
            }
            throw ApiError(code, msg, json)
        }
        if (json.length() == 0 && text.isNotBlank()) throw ApiError(code, "The website did not answer as expected (check the address).")
        return json
    }

    fun get(route: String, query: Map<String, String> = emptyMap()): JSONObject = read(open(url(route, query), "GET"))

    fun post(route: String, form: Map<String, String>): JSONObject {
        val c = open(url(route), "POST")
        c.doOutput = true
        c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
        val body = form.entries.joinToString("&") { enc(it.key) + "=" + enc(it.value) }.toByteArray()
        c.setFixedLengthStreamingMode(body.size)
        c.outputStream.use { it.write(body) }
        return read(c)
    }

    /** Sends one piece of a file. */
    fun chunk(id: String, offset: Long, data: ByteArray, len: Int): JSONObject {
        val c = open(url("upload/chunk", mapOf("id" to id, "offset" to offset.toString())), "POST")
        c.doOutput = true
        c.setRequestProperty("Content-Type", "application/octet-stream")
        c.setFixedLengthStreamingMode(len)
        c.readTimeout = 120000
        c.outputStream.use { it.write(data, 0, len) }
        return read(c)
    }
}
