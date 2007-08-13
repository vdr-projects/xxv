var ttp_content;
ttp_content = "";

var ttp_timer;
var ttp_x = -1;
var ttp_y = -1;
var ttp_visable = 0;
var ttp_offset_x = 0;
var ttp_x_start = -1;
var ttp_y_start = -1;

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

if(ttp_visable) {
  if(Math.abs(ttp_x_start - ttp_x) > 5
   || Math.abs(ttp_y_start - ttp_y) > 5) {
    ttp_make_invisable(this);
  }
  ttp_update_pos();
  }
}


function ttp_update_content(title, description){
  var utitle = unescape(title);
  ttp_content =  '<div id="ttwindow"><p class="topic">';
  ttp_content += utitle.substr(0,50);
  if (utitle.length > 50)  {ttp_content += '...';}
  ttp_content += '</p><p class="description">'
  if(description == 'WAIT') {
    ttp_content += '<img src="images/wait.gif" alt="" />';
  } else {
    ttp_content += unescape(description);
  }
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

function ttp_make_req_visable(title, eventid, x, y){

    if(!eventid || eventid<=0
      || Math.abs(x - ttp_x) > 20
      || Math.abs(y - ttp_y) > 20) {
        return false;
    }
  	ttp_update_pos();
    ttp_update_content(title,'WAIT');

		document.getElementById('TOOLTIP').innerHTML = ttp_content;
		document.getElementById('TOOLTIP').style.visibility = "visible";

		ttp_visable = 1;
    ttp_x_start = ttp_x;
    ttp_y_start = ttp_y;

    var fnWhenDone = function (oXML, sData) {

        var description = eval('(' + oXML.responseText + ')');
        var content;
        if(description && description.data && typeof(description.data) == 'string'){
            content = description.data.replace(/\r\n/g,'<br />');
        } else {
            content = '...';
        }

      	ttp_update_pos();
        ttp_update_content(title,content);

    		document.getElementById('TOOLTIP').innerHTML = ttp_content;
    		document.getElementById('TOOLTIP').style.visibility = "visible";
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
    ttp_timer = setTimeout("ttp_make_req_visable('"+escape(title)+"', '"+eventid+"', '"+ttp_x+"', '"+ttp_y+"')", 750);
	}
}

/** XHRequest based on                                                       **
 ** XHConn - Simple XMLHTTP Interface - bfults@gmail.com - 2005-04-08        **
 ** Code licensed under Creative Commons Attribution-ShareAlike License      **
 ** http://creativecommons.org/licenses/by-sa/2.0/                           **/

function XHRequest()
{
  var xmlhttp, bComplete = false;
  try { xmlhttp = new ActiveXObject("Msxml2.XMLHTTP"); }
  catch (e) { try { xmlhttp = new ActiveXObject("Microsoft.XMLHTTP"); }
  catch (e) { try { xmlhttp = new XMLHttpRequest(); }
  catch (e) { xmlhttp = false; }}}
  if (!xmlhttp) 
    return null;

  this.connect = function(sRequest, fnDone, sData)
              {
                if (!xmlhttp) return false;
                bComplete = false;

                try {
                     xmlhttp.open("GET", sRequest, true);
                     xmlhttp.onreadystatechange = function() 
                          {
                            if (xmlhttp.readyState == 4 && !bComplete)
                            {
                                bComplete = true;
                                fnDone(xmlhttp, sData);
                            }
                          };
                     xmlhttp.send(null);
                } catch(z) { alert(z); return false; }
                return true;
              };
  return this;
}
