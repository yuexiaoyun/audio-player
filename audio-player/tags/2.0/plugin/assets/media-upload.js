var send_to_editor;

addLoadEvent(function () {
	if (send_to_editor !== undefined) {
    send_to_editor_backup = send_to_editor;
    
    send_to_editor = function(h) {
		  var matches = h.match(/<a ([^=]+=['\"][^\"']+['\"] )*href=['\"](\[audio:([^\"']+\.mp3)])['\"]( [^=]+=['\"][^\"']+['\"])*>([^<]*)<\/a>/i);
      if (matches) {
        h = matches[2];
				if (matches[5].length > 0) {
	        h = h.replace(/]$/i, "|titles=" + matches[5] + "]");
				}
      }
      return send_to_editor_backup.call(this, h);
    };
	}
});