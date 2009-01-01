/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.RemoteWindow = function() {

    var data = { lines : [
          { next: 0, x : [
        { alias  : 'Switch off', remote : 'Power', image  : 'logout' }
      ] },{ next: 0, x : [
        { alias  : ' 1 ',          remote : '1',     image  : 0 },
        { alias  : ' 2 ',          remote : '2',     image  : 0 },
        { alias  : ' 3 ',          remote : '3',     image  : 0 }
      ] },{ next: 0, x : [
        { alias  : ' 4 ',          remote : '4',     image  : 0 },
        { alias  : ' 5 ',          remote : '5',     image  : 0 },
        { alias  : ' 6 ',          remote : '6',     image  : 0 }
      ] },{ next: 0, x : [
        { alias  : ' 7 ',          remote : '7',     image  : 0 },
        { alias  : ' 8 ',          remote : '8',     image  : 0 },
        { alias  : ' 9 ',          remote : '9',     image  : 0 }
      ] },{ next: 0, x : [
        { alias  : ' 0 ',        remote : 'Null',   image  : 0 },
        { alias  : 'Up',         remote : 'Up',     image  : 'up' }
      ] },{ next: 0, x : [
        { alias  : 'Left',       remote : 'Left',   image  : 'left' },
        { alias  : 'Ok',         remote : 'Ok',     image  : 0 },
        { alias  : 'Right',      remote : 'Right',  image  : 'right' }
      ] },{ next: 0, x : [
        { alias  : 'Menu',       remote : 'Menu',   image  : 'menu' },
        { alias  : 'Down',       remote : 'Down',   image  : 'down' },
        { alias  : 'Back',       remote : 'Back',   image  : 'back' }
      ] },{ next: 1, x : [
        { alias  : 'Red',        remote : 'Left',   image  : 'red' },
        { alias  : 'Green',      remote : 'Green',  image  : 'green' },
        { alias  : 'Yellow',     remote : 'Yellow', image  : 'yellow' },
        { alias  : 'Blue',       remote : 'Blue',   image  : 'blue' }
      ] },{ next: 0, x : [
        { alias  : 'Record',     remote : 'Record', image  : 'record' },
        { alias  : 'Playback',   remote : 'Play',   image  : 'playback' },
        { alias  : 'Pause',      remote : 'Pause',  image  : 'pause' },
        { alias  : 'Stop',       remote : 'Stop',   image  : 'stop' }
      ] },{ next: 0, x : [
        { alias  : 'FastRew',         remote : 'FastRew',     image  : 'backward' },
        { alias  : 'Decrease volume', remote : 'VolumeMinus', image  : 'quiet' },
        { alias  : 'Increase volume', remote : 'VolumePlus',  image  : 'loud' },
        { alias  : 'FastFwd',         remote : 'FastFwd',     image  : 'forward' }
      ] }
    ]};
    var tpl = new Ext.XTemplate(
'<div id="remote-tpl" class="x-window-mc" style="border:none">',
'<div class="x-panel-btns-ct">',
'<div class="x-panel-btns x-panel-btns-center">',
  '<table>',
    '<tpl for=".">',
      '<tpl if="next != 0">',
      '</tr>',
    '</table>',
    '<table>',
      '</tpl>',
      '<tr>',
      '<tpl for="x">',
        '<td class="x-panel-btn-td">',
         '<table cellspacing="0" cellpadding="0" border="0" class="x-btn-wrap x-btn" style="width: 32px;overflow:hidden">',
         '<tbody><tr><td class="x-btn-left"><i> </i></td><td class="x-btn-center">',
           '<button id="rcbt" class="x-btn-text" name="{alias}" type="button" value="{remote}"',
           'onclick="var ctrl = Ext.getCmp(\'Remote-win\');ctrl.onRemote(\'{remote}\');return false;">',
            '<tpl if="image == 0">{alias}</tpl>',
            '<tpl if="image != 0"><img alt="{alias}" title="{alias}" src="pic/{image}.png" width="16px" height="16px"></tpl>',
           '</button>',
          '</td><td class="x-btn-right"><i> </i></td></tr></tbody></table><td>',
      '</tpl>',
      '</tr>',
    '</tpl>',
  '</table>',
'</div>',
'</div>',
'</div>'
   );


    Ext.xxv.RemoteWindow.superclass.constructor.call(this, {
         title: this.szTitle
        ,Remotetpl:tpl
        ,iconCls: 'remote-icon'
        ,id: 'Remote-win'
        ,width: 200
        ,height: 340
        ,resizable: false
        ,plain: true
        ,modal: false
        ,autoScroll: false
        ,closeAction: 'hide'
        ,collapsible: true
        ,maximizable: false
        ,items: [{
           id: 'Remote'
          ,region: 'center'
          ,html: tpl.apply(data.lines)
        }]
    });

    Ext.xxv.RemoteWindow.superclass.show.apply(this, arguments);
}

Ext.extend(Ext.xxv.RemoteWindow, Ext.Window, {

    szTitle         : "Remote control"
    //,szRemoteSuccess : "Successful transmit remote control data.\r\n{0}"
    ,szRemoteFailure : "Couldn't transmit remote control data!\r\n{0}"
    ,hide : function(){
        if(this.task) {
          Ext.TaskMgr.stop(this.task);
          delete this.task;
        }

        Ext.xxv.RemoteWindow.superclass.hide.apply(this, arguments);
    }
    ,show : function(){
        Ext.xxv.RemoteWindow.superclass.show.apply(this, arguments);
    }
/******************************************************************************/
  ,onRemoteSuccess : function( response,options ) 
  { 
      var json = response.responseText;
      var o = eval("("+json+")");
      if(!o || !o.data || typeof(o.data) != 'string') {
        throw {message: "Ajax.read: Json message not found"};
      }
      if(o.param && o.param.state && o.param.state == 'success') {
          //new Ext.xxv.MessageBox().msgSuccess(this.szRemoteSuccess, o.data);
      }else {
          new Ext.xxv.MessageBox().msgFailure(this.szRemoteFailure, o.data);
      }
  }
  ,onRemoteFailure : function( response,options ) 
  { 
      new Ext.xxv.MessageBox().msgFailure(this.szRemoteFailure, response.statusText);
  }
  ,onRemote : function( rc ) {
    if(this.Remotetid) Ext.Ajax.abort(this.Remotetid);
    this.Remotetid = Ext.Ajax.request({
        url: XXV.help.cmdAJAX('r',{ data: rc })
       ,success: this.onRemoteSuccess
       ,failure: this.onRemoteFailure
       ,scope:   this
    });
  }
});

Ext.xxv.RemoteWindowOpen = function(){
    var viewer = Ext.getCmp('main-tabs');
    if(!viewer.Remote){
      viewer.Remote = new Ext.xxv.RemoteWindow();
    } else {
      viewer.Remote.show();
    }
}
