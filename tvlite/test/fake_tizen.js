/* A stand-in for Samsung's webapis.avplay (and a little of tizen / webapis), for testing the app in
 * a desktop browser: records every call in window.__av.calls and plays a pretend stream that
 * reports its time like the TV does. Not part of the app (test/ is left out of the packages). */
(function () {
  var A = window.__av = { calls: [], state: 'NONE', url: '', time: 0, timer: null, listener: null, live: true, failNext: '' };
  function rec(name, args) { A.calls.push([name].concat([].slice.call(args))); }
  function tick() {
    clearInterval(A.timer);
    A.timer = setInterval(function () {
      if (A.state !== 'PLAYING') return;
      A.time += 500;
      if (A.listener && A.listener.oncurrentplaytime) A.listener.oncurrentplaytime(A.time);
    }, 500);
  }
  var avplay = {
    open: function (url) { rec('open', arguments); if (A.state !== 'NONE' && A.state !== 'IDLE') throw { name: 'InvalidStateError' }; A.url = url; A.state = 'IDLE'; A.time = 0; },
    close: function () { rec('close', arguments); clearInterval(A.timer); A.state = 'NONE'; A.listener = null; },
    stop: function () { rec('stop', arguments); clearInterval(A.timer); if (A.state !== 'NONE') A.state = 'IDLE'; },
    setListener: function (l) { rec('setListener', []); A.listener = l; },
    setDisplayRect: function () { rec('setDisplayRect', arguments); if (A.state === 'NONE') throw { name: 'InvalidStateError' }; },
    setDisplayMethod: function () { rec('setDisplayMethod', arguments); },
    setTimeoutForBuffering: function () { rec('setTimeoutForBuffering', arguments); },
    prepareAsync: function (ok, bad) {
      rec('prepareAsync', []);
      var why = A.failNext; A.failNext = '';
      setTimeout(function () {
        if (why) { bad && bad({ name: why }); return; }
        A.state = 'READY';
        if (A.listener) A.listener.onbufferingstart();
        ok && ok();
        setTimeout(function () { if (A.listener) A.listener.onbufferingcomplete(); }, 200);
      }, 300);
    },
    play: function () { rec('play', arguments); if (A.state !== 'READY' && A.state !== 'PAUSED' && A.state !== 'PLAYING') throw { name: 'InvalidStateError' }; A.state = 'PLAYING'; tick(); },
    pause: function () { rec('pause', arguments); if (A.state === 'PLAYING') A.state = 'PAUSED'; },
    seekTo: function (ms, ok) { rec('seekTo', arguments); A.time = ms; ok && setTimeout(ok, 50); },
    getState: function () { return A.state; },
    getCurrentTime: function () { return A.time; },
    getDuration: function () { return A.live ? 0 : 3600000; },
    getTotalTrackInfo: function () {
      return [{ type: 'VIDEO', index: 0, extra_info: '{"fourCC":"H264","Width":"1920","Height":"1080"}' },
              { type: 'AUDIO', index: 1, extra_info: '{"language":"eng","channels":"2"}' },
              { type: 'AUDIO', index: 2, extra_info: '{"language":"urd","channels":"2"}' },
              { type: 'TEXT', index: 3, extra_info: '{"track_lang":"eng","subtitle_type":"0"}' },
              { type: 'TEXT', index: 4, extra_info: '{"track_lang":"ara","subtitle_type":"0"}' }];
    },
    getCurrentStreamInfo: function () {
      return [{ type: 'VIDEO', index: 0, extra_info: '{"fourCC":"H264","Width":"1920","Height":"1080"}' },
              { type: 'AUDIO', index: A.audio || 1, extra_info: '{"language":"eng"}' }];
    },
    setSelectTrack: function (type, i) { rec('setSelectTrack', arguments); if (type === 'AUDIO') A.audio = i; },
    setSilentSubtitle: function (on) { rec('setSilentSubtitle', arguments); }
  };
  window.webapis = window.webapis || {};
  window.webapis.avplay = avplay;
})();
