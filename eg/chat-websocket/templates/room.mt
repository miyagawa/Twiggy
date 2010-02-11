? my ($host, $room) = @_
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
  if (!ws) return;

  var ident = el1.attr('value');
  if (ident) $.cookie(cookieName, ident, { path: '/chat' });
  var text = el.attr('value');
  if (!text) return;

  ws.send(JSON.stringify({ ident:ident, text:text }));
  el.attr('value', '');
  return;
}

$(function(){
    if ("WebSocket" in window) {
        ws = new WebSocket("ws://<?= $host ?>/ws/<?= $room ?>");
    }
    else {
        $("#content").text("This browser doesn't support WebSocket.");
        return;
    }

    if (ws) {
        ws.onmessage = function (ev) {
            try {
                var d = eval("("+ev.data+")");
                var src = d.avator || ("http://www.gravatar.com/avatar/" + $.md5(d.ident || 'foo'));
                var name = d.name || d.ident || 'Anonymous';
                var avatar = $('<img/>').attr('src', src).attr('alt', name);
                if (d.ident) {
                    var link = d.ident.match(/https?:/) ? d.ident : 'mailto:' + d.ident;
                    avatar = $('<a/>').attr('href', link).attr('target', '_blank').append(avatar);
                }
                avatar = $('<td/>').addClass('avatar').append(avatar);

                var message = $('<td/>').addClass('chat-message');
                if (d.text) message.text(d.text);
                if (d.html) message.html(d.html);

                message.find('a').oembed(null, { embedMethod:"append", maxWidth:500 });
                var name = d.name || (d.ident ? d.ident.split('@')[0] : null);
                if (name)
                    message.prepend($('<span/>').addClass('name').text(name+': '));

                var date = new Date(d.time * 1000);
                var meta = $('<td/>').addClass('meta').append(
                    '(' +
                        '<span class="pretty-time" title="' + date.toUTCString() + '">' + date.toDateString() + '</span>' +
                        ' from ' + d.address + ')'
                );
                $('.pretty-time', meta).prettyDate();
                $('#messages').prepend($('<tr/>').addClass('message').append(avatar).append(message).append(meta));
                
            } catch(e) { if (console) console.log(e) }
        }
    }

    if ($.cookie(cookieName))
        $('#ident').attr('value', $.cookie(cookieName));

    window.setInterval(function(){ $(".pretty-time").prettyDate() }, 1000 * 30);
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

<h1 class="chat-room-name">Chat room: <?= $room ?></h1>
<!-- move this input out of form so Firefox can submit with enter key :/ -->
Your email (for Gravatar): <input id="ident" type="text" name="ident" size="24"/>
<form onsubmit="doPost($('#ident'), $('#chat')); return false">
Something to say: <input id="chat" type="text" size="48"/>
</form>

<table id="messages">
</table>

<div id="footer">Powered by <a href="http://github.com/miyagawa/Twiggy">Twiggy/<?= $AnyEvent::Server::PSGI::Twiggy::VERSION ?></a>.</div>

</div>
</body>
</html>