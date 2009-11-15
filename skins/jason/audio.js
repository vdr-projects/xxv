/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.AudioWindow = function(item) {

    var width = 320;
    var height = 29;
    var marginHeight = 30;
    var marginWidth = 16;

    AudioPlayer.setup("audio-player/player.swf", { 
      width: 320  
      ,animation: "no"
      ,transparentpagebg: "yes"
    });

    this.item = item;
    Ext.xxv.AudioWindow.superclass.constructor.call(this, {
         title: this.szTitle
        ,iconCls: 'music-icon'
        ,id: 'audio-win'
        ,width: width + marginWidth
        ,height: height + marginHeight
        ,resizable: false
        ,plain: true
        ,modal: false
        ,autoScroll: false
        ,closeAction: 'hide'
        ,maximizable: false
        ,stateful: true
        ,items: [{
          // id:'audio-player'
           region: 'center'
          ,width: width
          ,height: height
          ,html: "<div id='audio-player'></div>"
        }]
    });
    this.on('beforeshow', this.onBeforeShow, this);
    Ext.xxv.AudioWindow.superclass.show.apply(this, arguments);
}

Ext.extend(Ext.xxv.AudioWindow, Ext.Window, {
    szTitle: "Music playback"
    ,onBeforeShow : function(){
        if(!this.embed){
          for(var i = 0, len = this.item.url.length; i < len; i++){
            this.item.url[i] = escape(this.item.url[i]);
          }
          AudioPlayer.embed('audio-player', {
             soundFile: this.item.url.join(',')
            ,titles: this.item.title.join(',')
            ,artists: this.item.artist.join(',')
            ,autostart: 'yes'
            ,loader:'404040'
          });
          this.embed = true;
        }
    }
    ,hide : function(){
        if(this.embed) {
          AudioPlayer.close('audio-player');
        }
        Ext.xxv.AudioWindow.superclass.hide.apply(this, arguments);
    }
    ,show : function(item){
        if(this.embed) {
          AudioPlayer.load('audio-player',item.url.join(','),item.title.join(','),item.artist.join(','));
          AudioPlayer.open('audio-player');
        }
        Ext.xxv.AudioWindow.superclass.show.apply(this, arguments);
    }
});
