/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.StreamWindow = function(item) {

    var tpl = new Ext.XTemplate(
        '<object id="player_obj" width="{width}" height="{height}"',
          'classid="CLSID:22d6f312-b0f6-11d0-94ab-0080c74c7e95"',
          'codebase="http://activex.microsoft.com/activex/controls/mplayer/en/nsmp2inf.cab#Version=5,1,52,701"',
          'standby="Loading Microsoft Windows Media Player components..." type="application/x-oleobject">',
          '<param name="fileName" value="{url}" />',
          '<param name="animationatStart" value="false" />',
          '<param name="transparentatStart" value="false" />',
          '<param name="autoStart" value="true" />',
          '<param name="showControls" value="false" />',
          '<param name="loop" value="false" />',
          '<embed id="player_emb" width="{width}" height="{height}" src="{url}" ',
            'type="application/x-mplayer2" ',
            'pluginspage="http://microsoft.com/windows/mediaplayer/en/download/" ',
            'autosize="-1" showcontrols="false" showtracker="-1" ',
            'showdisplay="0" showstatusbar="-1" videoborder3d="-1" ',
            'autostart="true" loop="false" />',
        '</object>'
    );


    var width = configuration.streamWidth;
    var height = configuration.streamHeight;
    if(Ext.state.Manager.getProvider()) {
        var streamwin = Ext.state.Manager.get('stream-win');
        if(streamwin && streamwin.width && streamwin.width >= 160 && streamwin.width <= 4096) {
          width = streamwin.width;
        }
        if(streamwin && streamwin.height && streamwin.height >= 120 && streamwin.height <= 2048) {
          height = streamwin.height;
        }
    }
    var marginHeight = 33;
    var marginWidth = 16;
    
    Ext.xxv.StreamWindow.superclass.constructor.call(this, {
         title: item.title
        ,streamtpl:tpl
        ,iconCls: 'stream-icon'
        ,id: 'stream-win'
        ,minWidth: 160
        ,minHeight: 120
        ,marginWidth: marginWidth
        ,marginHeight: marginHeight
        ,width: width
        ,height: height
        ,resizable: true
        ,plain: true
        ,modal: false
        ,autoScroll: false
        ,closeAction: 'hide'
        ,collapsible: true
        ,maximizable: true
        ,tools:[
          {id:'gear',handler:this.aspect, scope:this }
        ]
        ,items: [{
           id: 'video'
          ,region: 'center'
          ,width: width - marginWidth
          ,height: height - marginHeight
          ,html: tpl.apply({
                width : width - marginWidth,
                height : height - marginHeight,
                url: item.url
              })
        }]
    });

    Ext.xxv.StreamWindow.superclass.show.apply(this, arguments);

    this.on('resize', this.onresize, this);
}

Ext.extend(Ext.xxv.StreamWindow, Ext.Window, {
    aspect : function() {
        var size = this.getSize();
        this.setSize(size.width, Math.round((size.width * 3) / 4));
    }
    ,onresize : function(window, width, height ){
        width -= this.marginWidth;
        height -= this.marginHeight;

        var video = Ext.getCmp('video');
        video.setWidth(width);
        video.setHeight(height);

        var style = {width:width+"px",height:height+"px"};
        Ext.DomHelper.applyStyles('player_obj', style);
        Ext.DomHelper.applyStyles('player_emb', style);

    },

    hide : function(){
        var video = Ext.getCmp('video');
        if(video && video.body) video.body.update('');
        Ext.xxv.StreamWindow.superclass.hide.apply(this, arguments);
    },
    show : function(item){
        if(this.rendered){
          var video = Ext.getCmp('video');
          var size = this.getSize();
          video.body.hide();
          this.streamtpl.overwrite(video.body, {
                width : size.width - this.marginWidth,
                height : size.height - this.marginHeight,
                url: item.url
              });
          video.body.show();
          this.setTitle(item.title);
        }
        Ext.xxv.StreamWindow.superclass.show.apply(this, arguments);
    }
});
