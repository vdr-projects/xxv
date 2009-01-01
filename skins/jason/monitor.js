/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.MonitorWindow = function() {

    var tpl = new Ext.XTemplate(
      '<img id="monitor_img" src="?cmd=gdisplay&amp;width={width}&amp;height={height}&amp;_dc={random}" width="{width}" height="{height}" />'
    );

    var width = configuration.monitorWidth;
    var height = configuration.monitorHeight;
    if(Ext.state.Manager.getProvider()) {
        var monitorwin = Ext.state.Manager.get('monitor-win');
        if(monitorwin && monitorwin.width && monitorwin.width >= 160 && monitorwin.width <= 4096) {
          width = monitorwin.width;
        }
        if(monitorwin && monitorwin.height && monitorwin.height >= 120 && monitorwin.height <= 2048) {
          height = monitorwin.height;
        }
    }
    var marginHeight = 33;
    var marginWidth = 16;
    
    Ext.xxv.MonitorWindow.superclass.constructor.call(this, {
         title: this.szTitle
        ,monitortpl:tpl
        ,iconCls: 'monitor-icon'
        ,id: 'monitor-win'
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
          {id:'gear',handler:this.aspect, scope:this },
          {id:'refresh',handler:this.update, scope:this }
        ]
        ,items: [{
           id: 'monitor'
          ,region: 'center'
          ,width: width - marginWidth
          ,height: height - marginHeight
          ,html: tpl.apply({
                width : width - marginWidth,
                height : height - marginHeight,
                random: (new Date().getTime())
              })
        }]
    });

    Ext.xxv.MonitorWindow.superclass.show.apply(this, arguments);

    this.on('resize', this.onresize, this);

    this.task = Ext.TaskMgr.start({
        run: this.update,
        scope: this,
        interval:10000
    });
}

Ext.extend(Ext.xxv.MonitorWindow, Ext.Window, {

    szTitle         : "Monitor"
    ,aspect : function() {
        var size = this.getSize();
        this.setSize(size.width, Math.round((size.width * 3) / 4));
    }
    ,onresize : function(window, width, height ){
        width -= this.marginWidth;
        height -= this.marginHeight;

        var monitor = Ext.getCmp('monitor');
        monitor.setWidth(width);
        monitor.setHeight(height);

        var style = {width:width+"px",height:height+"px"};
        Ext.DomHelper.applyStyles('monitor_img', style);
    }
    ,hide : function(){
        if(this.task) {
          Ext.TaskMgr.stop(this.task);
          delete this.task;
        }

        Ext.xxv.MonitorWindow.superclass.hide.apply(this, arguments);
    }
    ,show : function(){
        if(this.rendered){

          if(!this.task) {
            this.task = Ext.TaskMgr.start({
                run: this.update,
                scope: this,
                interval:10000
            });
          }
        }
        Ext.xxv.MonitorWindow.superclass.show.apply(this, arguments);

    }
   ,update : function(){
          var monitor = Ext.getCmp('monitor');
          if(!monitor) {  
            return;
          }
          var size = monitor.getSize();
          if(!size) {  
            return;
          }
          var img = Ext.getDom('monitor_img');
          if(!img) {  
            return;
          }
          img.src = '?cmd=gdisplay&width='+ size.width +'&height='+ size.height +'&_dc=' + (new Date().getTime());
    }
});

Ext.xxv.MonitorWindowOpen = function(){
    var viewer = Ext.getCmp('main-tabs');
    if(!viewer.monitor){
      viewer.monitor = new Ext.xxv.MonitorWindow();
    } else {
      viewer.monitor.show();
    }
}
