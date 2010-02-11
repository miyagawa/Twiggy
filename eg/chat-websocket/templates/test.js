$(function(){
    if ("WebSocket" in window) {
        ws = new WebSocket("ws://<?= $host ?>:<?= $port ?>/service");
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
