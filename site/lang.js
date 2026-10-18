// 첫 쪽에 온 사람을 브라우저 언어에 맞는 쪽으로 보낸다. 스크립트가 꺼져 있으면 쪽에 있는 링크로 고르면 된다.
(function () {
  var langs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || ''];
  for (var i = 0; i < langs.length; i++) {
    var l = String(langs[i]).toLowerCase();
    if (l.indexOf('ko') === 0) return location.replace('/ko/');
    if (l.indexOf('ja') === 0) return location.replace('/ja/');
    if (l.indexOf('en') === 0) return location.replace('/en/');
  }
  location.replace('/en/');
})();
