var ttp_content;
ttp_content = "";

var ttp_timer;
var ttp_x = -1;
var ttp_y = -1;
var ttp_visable = 0;
var ttp_offset_x = 0;

function ttp_update_pos(){
		document.getElementById('TOOLTIP').style.left = (ttp_offset_x + ttp_x) + "px";
		document.getElementById('TOOLTIP').style.top  = (ttp_y + 20) + "px";
}

var ttp_ie = document.all?true:false;
if (!ttp_ie) document.captureEvents(Event.MOUSEMOVE)
document.onmousemove = ttp_onmousemove;

function ttp_onmousemove(e) {
if (ttp_ie) { 
  ttp_x = event.clientX + document.body.scrollLeft;
  ttp_y = event.clientY + document.body.scrollTop;
} else { 
  ttp_x = e.pageX;
  ttp_y = e.pageY;
}
if (ttp_x < 0)  {ttp_x = 0;}
if (ttp_y < 0)  {ttp_y = 0;}
if(ttp_visable) {ttp_update_pos();}
}


function ttp_update_content(title, description){
  var utitle = unescape(title);
  ttp_content =  '<div id="ttwindow"><p class="topic">';
  ttp_content += utitle.substr(0,50);
  if (utitle.length > 50)  {ttp_content += '...';}
  ttp_content += '</p><p class="description">'
  ttp_content += unescape(description);
  ttp_content += '</p></div>';
}

function ttp_make_visable(title, description){
		ttp_update_pos();
		document.getElementById('TOOLTIP').style.visibility = "visible";
		ttp_update_content(title, description);
		document.getElementById('TOOLTIP').innerHTML = ttp_content;
		ttp_visable = 1;
}

function ttp_make_invisable(self){
    clearTimeout(ttp_timer);
		ttp_visable = 0;
		document.getElementById('TOOLTIP').style.visibility = "hidden";
}

function ttp(self, title, description, offset_x){
  self.onmouseout=function(){ ttp_make_invisable(this); };
	if(description && ttp_x != -1 && ttp_y != -1){
    ttp_offset_x  = offset_x;
    ttp_timer = setTimeout("ttp_make_visable('"+escape(title)+"', '"+escape(description)+"')", 750);
	}
}

function ttp_make_req_visable(title, eventid){

    if(!eventid || eventid<=0)
      return false;
    var fnWhenDone = function (oXML, sData) {

        var description = eval('(' + oXML.responseText + ')');

        if(description && description.data && typeof(description.data) == 'string'){
            var content = description.data.replace(/\r\n/g,'<br />');

          	ttp_update_pos();
            ttp_update_content(title,content);

        		document.getElementById('TOOLTIP').innerHTML = ttp_content;
        		document.getElementById('TOOLTIP').style.visibility = "visible";

        		ttp_visable = 1;
        }
    };

    var url = "?cmd=edescription&data=" + eventid + "&ajax=json";
    var aconn = new XHRequest();
    if(!aconn)
      return false;
    return aconn.connect(url, fnWhenDone, eventid);
}


function ttpreq(self, title, eventid, offset_x){
  self.onmouseout=function(){ ttp_make_invisable(this); };
	if(eventid && ttp_x != -1 && ttp_y != -1){
    ttp_offset_x  = offset_x;
    ttp_timer = setTimeout("ttp_make_req_visable('"+escape(title)+"', '"+eventid+"')", 750);
	}
}
