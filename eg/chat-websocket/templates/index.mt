<html>
<head>
<title>Twiggy/Plack WebSocket Chat demo</title>
<script src="/static/jquery-1.3.2.min.js"></script>
<script src="/static/jquery.ev.js"></script>
<script src="/static/jquery.md5.js"></script>
<script src="/static/jquery.cookie.js"></script>
<script src="/static/jquery.oembed.js"></script>
<script src="/static/pretty.js"></script>
<script>
var ws;
var cookieName = 'tatsumaki_chat_ident';

function doPost(el1, el) {
  var text = el.attr('value');
  location.href = 'http://' + location.host + '/chat/' + text;
  return;
}

$(function(){
    if ("WebSocket" in window) {
    }
    else {
        $("#content").text("This browser doesn't support WebSocket.");
        return;
    }
});
</script>
<link rel="stylesheet" href="/static/screen.css" />
<style>
#messages {
  margin-top: 1em;
  margin-right: 3em;
  width: 100%;
}
.avatar {
  width: 25px;
  vertical-align: top;
}
.avatar img {
  width: 25px; height: 25px;
  vertical-align: top;
  margin-right: 0.5em;
}
.chat-message {
  width: 70%;
}
.chat-message .name {
  font-weight: bold;
}
.meta {
  vertical-align: top;
  color: #888;
  font-size: 0.8em;
}
body {
  margin: 1em 2em
}

</style>
</head>
<body>

<div id="content">

<h1 class="chat-room-name">Enter room name:</h1>
<form onsubmit="doPost($('#ident'), $('#chat')); return false">
room name to enter: <input id="chat" type="text" size="48"/>
</form>

<table id="messages">
</table>

<div id="footer">Powered by <a href="http://github.com/miyagawa/Twiggy">Twiggy/<?= $Twiggy::VERSION ?></a>.</div>

</div>
</body>
</html>
