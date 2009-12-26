/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.searchStore = function(lookup) {
    return new Ext.data.GroupingStore({
            baseParams:{cmd:'s',data: lookup}
            ,autoLoad:{params:{start:0, limit:configuration.pageSize}}
            ,reader: new Ext.xxv.jsonReader({
                          fields: [
                                    {name: 'id', type: 'string'},
                                    {name: 'title', type: 'string'},
                                    {name: 'subtitle', type: 'string'},
                                    {name: 'channel', type: 'string'},
                                    {name: 'pos', type: 'int'},
                                    {name: 'start', type: 'string' },
                                    {name: 'stop', type: 'string' },
                                    {name: 'day', type: 'date', convert : function(x){ return new Date(x * 1000);}  },
                                    {name: 'description', type: 'string'},
                                    {name: 'vps', type: 'string' },
                                    {name: 'timerid', type: 'string'},
                                    {name: 'timeractiv', type: 'string'},
                                    {name: 'running', type: 'string'},
                                    {name: 'video', type: 'string'},
                                    {name: 'audio', type: 'string'}
                                  ],
                          remoteGroup:true,
                          remoteSort: true
                      })
            ,proxy : new Ext.data.HttpProxy({
                 url: XXV.help.baseURL()
                ,method: 'POST'
            })
            ,sortInfo:{field:'day', direction:'ASC'}
            ,groupField:'day'
    });
};

Ext.xxv.searchGrid = function(viewer, lookup) {

    this.viewer = viewer;
    this.preview = new Ext.xxv.searchPreview(viewer);
    //Ext.apply(this, config);

    // create the data store
    this.store = new Ext.xxv.searchStore(lookup);
    this.store.setDefaultSort('day', "ASC");

    this.columns = [{
            header: this.szColTitle
           ,dataIndex: 'title'
           ,width: 150
           ,renderer: { fn: this.viewer.gridNow.formatTitle, scope: this.viewer.gridNow }
        },{           header: this.szColChannel,
           dataIndex: 'channel',
           width: 100
        },{           header: this.szColDay,
           dataIndex: 'day',
           width: 50,
           hidden: true,
           renderer: Ext.util.Format.dateRenderer(this.szColDayFormat)
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

    Ext.xxv.searchGrid.superclass.constructor.call(this, {
        region: 'center',
        id: 'search-grid',
        loadMask: false,
        sm: new Ext.grid.RowSelectionModel({
            singleSelect:false
        }),
        autoExpandColumn:'title',
        view: new Ext.grid.GroupingView({
            enableGroupingMenu:false,
            forceFit:true,
            showGroupName: false
        }),
        tbar:new Ext.PagingToolbar({
          pageSize: this.store.autoLoad.params.limit,
          store: this.store,
          displayInfo: true })
    });

    this.store.on({
         'load' :          this.onLoad
        ,'beforeload'    : this.onBeforeLoad
        ,'loadexception' : this.onLoadException
        ,scope:this
    });
    this.on('rowcontextmenu', this.onContextClick, this);
    this.getSelectionModel().on('rowselect', this.select, this, {buffer:50});
};

Ext.extend(Ext.xxv.searchGrid, Ext.grid.GridPanel, {

     szTitle         : "Search"
    ,szFindReRun     : "Find rerun"
    ,szRecord        : "Record"
    ,szColTitle      : "Title"
    ,szColChannel    : "Channel"
    ,szColDay        : "Day"
    ,szColStart      : "Start"
    ,szColStop       : "Stop"
    ,szColDayFormat  : "l, m/d/Y"
    ,szLoadException : "Couldn't find data!\r\n{0}"

    ,stateful:  true

    ,onLoadException :  function( scope, o, arg, e) {
      new Ext.xxv.MessageBox().msgFailure(this.szLoadException, e.message);
    }
    ,onBeforeLoad : function(  store, opt ) {
      this.preview.clear();
    }
    ,onLoad : function( store, records, opt ) {
      this.getSelectionModel().selectFirstRow();
      this.ownerCt.SetPanelTitle(store.baseParams.data);
    }

    ,onContextClick : function(grid, index, e){
        if(!this.menu){ // create context menu on first right click
            this.menu = new Ext.menu.Menu({
                id:'grid-ctx',
                items: [
                    {
                     itemId: 's'
                    ,iconCls: 'find-icon'
                    ,text: this.szFindReRun
                    ,scope:this
                    ,disabled: true
                    ,handler: function(){ this.viewer.searchTab(this.ctxRecord); }
                    }
                   ,{
                     itemId: 'tn'
                    ,text: this.szRecord
                    ,iconCls: 'record-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function(){ this.Record(null); }
                    },{
                     itemId:'te'
                    ,text: this.viewer.gridNow.szEditTimer
                    ,iconCls: 'timer-edit-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function() { this.EditTimer(this.ctxRecord); }
                    },{
                     itemId:'td'
                    ,text: this.viewer.gridNow.szDeleteTimer
                    ,iconCls: 'timer-delete-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function() { this.DeleteTimer(this.ctxRecord); }
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

        var timerid = this.ctxRecord.data.timerid;
        var items = this.menu.items;
        if(items) { items.eachKey(function(key, f) { 
                      if(f.itemId == 'tn') { if(timerid) f.hide(); else f.show(); }
                      else if(f.itemId == 'te') { if(timerid) f.show(); else f.hide(); }
                      else if(f.itemId == 'td') { if(timerid) f.show(); else f.hide(); }
                      if(XXV.help.cmdAllowed(f.itemId)) 
                        f.enable();
                      },items); 
                  }

        this.menu.showAt(e.getXY());
    }

    ,onContextHide : function(){
        if(this.ctxRow){
            Ext.fly(this.ctxRow).removeClass('x-node-ctx');
            this.ctxRow = null;
        }
        if(this.menu) {
          this.menu.destroy();
          delete this.menu;
          this.menu = null;
        }
    }

    ,loadSearch : function(lookup) {
        this.store.baseParams.data = lookup;
        this.store.load({params:{start:0, limit:this.store.autoLoad.params.limit}});
    }
    ,Record : function( record ) {
      var gsm = this.getSelectionModel();
      var sel = gsm.getSelections()
      if(sel.length <= 0) {
       gsm.selectRecords([record]);
       sel.push(record);
      }
      var ids = "";
      for(var i = 0, len = sel.length; i < len; i++){
        if(i != 0)
   	      ids += ',';
	      ids += sel[i].data.id;
      }
      this.viewer.RecordID(ids);
    }
    ,EditTimer : function(record) {
        this.viewer.gridNow.EditTimer(record, this.store);
    }
    ,DeleteTimer : function(record) {
        var gsm = this.getSelectionModel();
        var sel = gsm.getSelections()
        if(sel.length <= 0) {
         gsm.selectRecords([record]);
         sel.push(record);
        }
        var items = "";
        for(var i = 0, len = sel.length; i < len; i++){
          if(i != 0)
     	      items += ',';
          if(sel[i].data.timerid == 0) {
            continue;
          }
	        items += sel[i].data.timerid;
        }
        this.viewer.gridNow.DeleteTimerId(items, this.store);
    }
    ,select : function(sm, index, record){
      this.preview.select(record,this.store.baseParams.data);
    }
});

Ext.xxv.searchPreview = function(viewer) {
    this.viewer = viewer;
    Ext.xxv.searchPreview.superclass.constructor.call(this, {
        id: 'preview-Search',
        region: 'south',
        cls:'preview',
        autoScroll: true,
        stateful:true,
        tbar: [ {
            id:'s',
            tooltip: Ext.xxv.NowGrid.prototype.szFindReRun,
            iconCls: 'find-icon',
            disabled:true,
            scope: viewer,
            handler: function(){ this.searchTab(this.gridSearch.getSelectionModel().getSelected()); }
        } ,{
            id:'tn',
            tooltip: this.viewer.gridNow.szRecord,
            iconCls: 'record-icon',
            disabled:true,
            scope: viewer,
            handler: function(){ this.Record(this.gridSearch.getSelectionModel().getSelected()); }
        },{
            id:'te',
            tooltip: this.viewer.gridNow.szEditTimer,
            iconCls: 'timer-edit-icon',
            disabled:true,
            scope: viewer,
            handler: function(){
              this.gridSearch.EditTimer(this.gridSearch.getSelectionModel().getSelected()); 
            }
        },{
            id:'td',
            tooltip: this.viewer.gridNow.szDeleteTimer,
            iconCls: 'timer-delete-icon',
            disabled:true,
            scope: viewer,
            handler: function(){
              this.gridSearch.DeleteTimer(this.gridSearch.getSelectionModel().getSelected()); 
            }
        } ]
    });
};
Ext.extend(Ext.xxv.searchPreview, Ext.Panel, {
  select : function(record, lookup){
    if(this.body)
      XXV.getTemplate().overwrite(this.body, record.data);
    if(lookup)
      highlightText(this.body.dom,lookup,'x-highlight',1);
    // Enable all toolbar buttons
    var items = this.topToolbar.items;
    var items = this.topToolbar.items;
    if(items) { 
        items.eachKey(function(key, f) {
                  if(f.id == 'tn')      { if(record.data.timerid) f.hide(); else f.show(); }
                  else if(f.id == 'te') { if(record.data.timerid) f.show(); else f.hide(); }
                  else if(f.id == 'td') { if(record.data.timerid) f.show(); else f.hide(); }
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

function createSearchView(viewer,id,lookup) {

    viewer.gridSearch = new Ext.xxv.searchGrid(viewer, lookup);
  
    tab = new Ext.xxv.Panel({
      id: id,
      iconCls: 'find-icon',
      closable:true,
      autoScroll:true,
      border:false,
      layout:'border',
      stateful:true,
      items:[
            viewer.gridSearch,
            {
              id:'search-bottom-preview',
              layout:'fit',
              items:XXV.BottomPreview ? 0 : viewer.gridSearch.preview,
              height: 250,
              split: true,
              border:false,
              region:'south',
              hidden:XXV.BottomPreview
            }, {
              id:'search-right-preview',
              layout:'fit',
              items:XXV.RightPreview ? 0 : viewer.gridSearch.preview,
              border:false,
              region:'east',
              width:350,
              split: true,
              hidden:XXV.RightPreview
            }
         ]
    });

    viewer.add(tab);

    return tab;
}

