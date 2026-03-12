// Copy Code — injects a Copy button into each code block.

(function() {
  var COPY = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path></svg>Copy';
  var COPIED = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path></svg>Copied!';

  function copyText(btn, pre) {
    var code = pre.querySelector('code');
    if (!code) return;
    navigator.clipboard.writeText(code.textContent).then(done, function() {
      var ta = document.createElement('textarea');
      ta.value = code.textContent;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      done();
    });
    function done() {
      btn.classList.add('copied');
      btn.innerHTML = COPIED;
      setTimeout(function() {
        btn.classList.remove('copied');
        btn.innerHTML = COPY;
      }, 2000);
    }
  }

  document.querySelectorAll('pre.mud-code').forEach(function(pre) {
    var header = pre.querySelector('.code-header');
    if (header && !header.offsetParent) header = null;
    var btn = document.createElement('button');
    btn.className = 'code-copy-btn';
    btn.innerHTML = COPY;
    btn.addEventListener('click', function() { copyText(btn, pre); });
    if (header) {
      header.appendChild(btn);
    } else {
      btn.classList.add('code-copy-floating');
      pre.appendChild(btn);
    }
  });
})();
