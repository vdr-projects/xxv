/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.NowStore = function() {
    return new Ext.data.GroupingStore({
             baseParams:{cmd:'n','__cgrp':'all'}
            ,autoLoad:{params:{start:0, limit:configuration.pageSize}}
            ,reader: new Ext.xxv.jsonReader({
                          fields: [
                                     {name: 'id', type: 'string'}
                                    ,{name: 'title', type: 'string'}
                                    ,{name: 'subtitle', type: 'string'}
                                    ,{name: 'channel', type: 'string'}
                                    ,{name: 'position', type: 'string'}
                                    ,{name: 'grpname', type: 'string'}
                                    ,{name: 'start', type: 'string' }
                                    ,{name: 'stop', type: 'string' }
                                    ,{name: 'description', type: 'string'}
                                    ,{name: 'prozent', type: 'string'}
                                    ,{name: 'timerid', type: 'string'}
                                    ,{name: 'timeractiv', type: 'string'}
                                    ,{name: 'running', type: 'string'}
                                    ,{name: 'vps', type: 'string'} //type:'date', dateFormat:'timestamp'}
                                    ,{name: 'rang', type: 'int'} //dummy field created after onload
                                  ]
                      })
            ,proxy : new Ext.data.HttpProxy({
                url: XXV.help.baseURL()
                ,method: 'GET'
            })
            ,sortInfo:{field:'rang', direction:'ASC'}
            ,groupField:'grpname'
            ,remoteGroup:true
    });
}

Ext.xxv.NowGrid = function(viewer) {

    this.viewer = viewer;
    this.preview = new Ext.xxv.NowPreview(viewer);

    // create the data store
    this.store = new Ext.xxv.NowStore();
    this.store.setDefaultSort('rang', "ASC");

    var range = new Array();
    range.push([this.szPresent,0]);
    range.push([this.szFollowing,1]);
    for(var i = 0, len = configuration.periods.length; i < len; i++){
      range.push([configuration.periods[i],configuration.periods[i]]);
    }

    this.timefield = new Ext.form.ComboBox({
                id:'timefield'
                ,width:75
                ,store: new Ext.data.Store({
                    reader: new Ext.data.ArrayReader({}, [{name: 'display'},{name: 'value'} ]),
                    data: range
                })
                ,displayField:'display'
                ,valueField:'value'
                ,triggerAction: 'all'                ,lazyRender:true
                ,listClass: 'x-combo-list-small'
                ,mode: 'local'
                ,emptyText:new Date().dateFormat('H:i')
                ,selectOnFocus:true
                ,editable: false
				        ,listeners: {
						      'select': {fn:this.reload, scope:this}
						      //'valid': {fn:this.reload, scope:this}
				        }
            });

    this.columns = [
        {           header: this.szColPosition,
           dataIndex: 'rang',
           width: 20,
           hidden: true
        },{
           header: this.szColTitle,
           dataIndex: 'title',
           width: 150,
           renderer: this.formatTitle
        },{           header: this.szColChannel,
           dataIndex: 'channel',
           width: 50
        },{           header: this.szColGrpName,
           dataIndex: 'grpname',
           width: 50,
           hidden: true
        },{
           header: this.szColStart,
           dataIndex: 'start',
           width: 50
        },{
           header: this.szColStop,
           dataIndex: 'stop',
           width: 50
        }
    ];

    var cm = new Ext.grid.ColumnModel(this.columns);
    cm.defaultSortable = true;

    Ext.xxv.NowGrid.superclass.constructor.call(this, {
        region: 'center'
        ,id: 'now-grid'
        ,loadMask: true
        ,autoExpandColumn:'title'
        ,cm: cm
        ,sm: new Ext.grid.RowSelectionModel({
            singleSelect:true
        })
        ,view: new Ext.grid.GroupingView({
             enableGroupingMenu:false
            ,forceFit:true
            ,showGroupName: false
        })
        ,tbar:new Ext.PagingToolbar({
             pageSize: configuration.pageSize
            ,store: this.store
            ,displayInfo: true
            ,items:['->', this.timefield ]
        })
    });

    this.store.on({
         'load' :          this.onLoad
        ,'beforeload'    : this.onBeforeLoad
        ,'loadexception' : this.onLoadException
        ,scope:this
    });
    this.on('rowcontextmenu', this.onContextClick, this);
    this.getSelectionModel().on('rowselect', this.preview.select, this.preview, {buffer:50});
    this.on('rowdblclick', this.onSelectProgram, this);
};

Ext.extend(Ext.xxv.NowGrid, Ext.grid.GridPanel, {

     szTitle         : "Program guide"
    ,szPresent       : "Present"
    ,szFollowing     : "Following"
    ,szFindReRun     : "Find rerun"
    ,szProgram       : "Show program"
    ,szRecord        : "Record"
    ,szColPosition   : "Channel position"
    ,szColTitle      : "Title"
    ,szColChannel    : "Channel"
    ,szColGrpName    : "Group of channel"
    ,szColStart      : "Start"
    ,szColStop       : "Stop"
    ,szLoadException : "Couldn't get data!\r\n{0}"
    ,szRecordSuccess : "Successful created timer.\r\n{0}"
    ,szRecordFailure : "Couldn't create timer!\r\n{0}"

    ,onLoadException :  function( scope, o, arg, e) {
      new Ext.xxv.MessageBox().msgFailure(this.szLoadException, e);
    }
    ,onBeforeLoad : function(  store, opt ) {
      if(this.getTopToolbar().displayEl) {
          var size = this.timefield.getSize();
          this.getTopToolbar().displayEl.setRight(30+size.width);
      }
      delete(this.store.baseParams['data']);
      var time = this.timefield.getValue();
      if(time && time != '1') {
        this.store.baseParams.data = time;
        this.store.baseParams.cmd = 'n';
      } else {
        this.timefield.emptyText = new Date().dateFormat('H:i');
        this.timefield.setValue(time);
        if(time != '1')
          this.store.baseParams.cmd = 'n';
        else
          this.store.baseParams.cmd = 'nx';
      }
      this.preview.clear();
    }
    ,onLoad : function( store, records, opt ) {
      var l = records.length;
      for (var i = 0; i < l; i++) {
        records[i].data.rang = i;
      }
      this.getSelectionModel().selectFirstRow();
      var time = this.timefield.getValue();
      if(time && time != '1') {
        if(store.reader.meta 
            && store.reader.meta.param 
            && store.reader.meta.param.zeit) {
          var datum = new Date(store.reader.meta.param.zeit * 1000);
          this.ownerCt.SetPanelTitle(datum.dateFormat('l - H:i'));
        } else {
          this.ownerCt.SetPanelTitle(this.szTitle + " - " + time);
        }
      } else {
        if(time != '1')
          this.ownerCt.SetPanelTitle(this.szPresent + " - " + this.timefield.emptyText);
        else
          this.ownerCt.SetPanelTitle(this.szFollowing + " - " + this.timefield.emptyText);
      }
    }
    ,onSelectProgram : function(grid, index, e) {
      e.stopEvent();
      if(this.ctxRow){
          Ext.fly(this.ctxRow).removeClass('x-node-ctx');
          this.ctxRow = null;
      }
      var record = this.store.getAt(index);
      var data = {'position':record.data.position,'name':record.data.channel};
      this.viewer.openProgram(data); 
    }
    ,onContextClick : function(grid, index, e){
        if(!this.menu){ // create context menu on first right click
            this.menu = new Ext.menu.Menu({
                id:'grid-ctx',
                items: [{
                    text: this.szFindReRun,
                    iconCls: 'find-icon',
                    scope:this,
                    handler: function(){ this.viewer.searchTab(this.ctxRecord); }
                    },{
                    text: this.szProgram,
                    iconCls: 'program-icon',
                    scope:this,
                    handler: function(){ 
                      var data = {'position':this.ctxRecord.data.position,'name':this.ctxRecord.data.channel};
                      this.viewer.openProgram(data); }
                    },{
                    text: this.szRecord,
                    iconCls: 'record-icon',
                    scope:this,
                    handler: function(){ this.Record(this.ctxRecord); }
                    }
                ]
            });
            this.menu.on('hide', this.onContextHide, this);
        }
        e.stopEvent();
        if(this.ctxRow){
            Ext.fly(this.ctxRow).removeClass('x-node-ctx');
            this.ctxRow = null;
        }
        this.ctxRow = this.view.getRow(index);
        this.ctxRecord = this.store.getAt(index);
        Ext.fly(this.ctxRow).addClass('x-node-ctx');
        this.menu.showAt(e.getXY());
    }

    ,onContextHide : function(){
        if(this.ctxRow){
            Ext.fly(this.ctxRow).removeClass('x-node-ctx');
            this.ctxRow = null;
        }
    }

    ,reload : function() {
        this.store.load({params:{start:0, limit:configuration.pageSize}});
    }

/******************************************************************************/
    ,onRecordSuccess : function( response,options ) 
    { 
        this.loadMask.hide();
        var json = response.responseText;
        var o = eval("("+json+")");
        if(!o || !o.data || typeof(o.data) != 'string') {
          throw {message: "Ajax.read: Json message not found"};
        }
        if(o.param && o.param.state && o.param.state == 'success') {
            new Ext.xxv.MessageBox().msgSuccess(this.szRecordSuccess, o.data);
        }else {
            new Ext.xxv.MessageBox().msgFailure(this.szRecordFailure, o.data);
        }
    }
    ,onRecordFailure : function( response,options ) 
    { 
        this.loadMask.hide();
        new Ext.xxv.MessageBox().msgFailure(this.szRecordFailure, response.statusText);
    }
    ,Record : function(record) {
        this.RecordID(record.data.id);
    }
    ,RecordID : function(id) {
        this.loadMask.show();
        Ext.Ajax.request({
              scope: this
             ,url: XXV.help.cmdAJAX('tn',{ data: id, '__fast':'1' })
             ,success: this.onRecordSuccess
             ,failure: this.onRecordFailure
          });
    }
    ,formatTitle: function(value, p, record) {
        return String.format(
                '<div class="topic"><b>{0}</b> <span class="subtitle">{1}</span></div>',
                value, record.data.subtitle
                );
    }
    ,formatRow: function(value, p, record) {
        return String.format(
                '<span style="color:red">{0}</span>',
                value
                );
    }
});

Ext.xxv.NowPreview = function(viewer) {
    this.viewer = viewer;
    Ext.xxv.NowPreview.superclass.constructor.call(this, {
        id: 'now-preview',
        region: 'south',
        cls:'preview',
        autoScroll: true,
        stateful:true,
        tbar: [ {
            id:'s',
            text: this.szFindReRun,
            iconCls: 'find-icon',
            disabled:true,
            scope: viewer,
            handler: function(){ this.searchTab(this.gridNow.getSelectionModel().getSelected()); }
        } ,{
            id:'tn',
            text: this.szRecord,
            iconCls: 'record-icon',
            disabled:true,
            scope: viewer,
            handler: function(){ this.Record(this.gridNow.getSelectionModel().getSelected()); }
        } ]
    });
};

Ext.extend(Ext.xxv.NowPreview, Ext.Panel, {
   szFindReRun : "Find rerun"
  ,szRecord : "Record"
  ,select : function(sm, index, record){
    if(this.body)
      XXV.getTemplate().overwrite(this.body, record.data);

    // Enable all toolbar buttons
    var items = this.topToolbar.items;
    if(items) { 
        items.eachKey(function(key, f) {
                        if(XXV.help.cmdAllowed(key)) f.enable();
                      },items); 
      }
  }
  ,clear: function(){
      if(this) {
        if(this.body)
           this.body.update('');
        // Disable all items
        var items = this.topToolbar.items;
        if(items) { items.eachKey(function(key, f){f.disable();},items); }
      }
   }
});

function creatNowView(viewer,id) {

    viewer.gridNow = new Ext.xxv.NowGrid(viewer);

    var tab = new Ext.xxv.Panel({
            id:id,
            stateful:true,
            iconCls: 'channel-icon',
            layout:'border',
            hideMode:'offsets',
            items:[
                viewer.gridNow,
            {
                id:'now-bottom-preview',
                layout:'fit',
                items:XXV.BottomPreview ? 0 : viewer.gridNow.preview,
                height: 250,
                split: true,
                border:false,
                region:'south',
                hidden:XXV.BottomPreview
            }, {
                id:'now-right-preview',
                layout:'fit',
                items:XXV.RightPreview ? 0 : viewer.gridNow.preview,
                border:false,
                region:'east',
                width:350,
                split: true,
                hidden:XXV.RightPreview
            }]
    });

    return tab;
}
