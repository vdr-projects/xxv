/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.programStore = function(data) {
    return new Ext.data.GroupingStore({
             title:data.name
            ,baseParams:{cmd:'p',data: data.position}
            ,autoLoad:{params:{start:0, limit:configuration.pageSize}}
            ,reader: new Ext.xxv.jsonReader({
                          fields: [
                                     {name: 'id', type: 'string'}
                                    ,{name: 'title', type: 'string'}
                                    ,{name: 'subtitle', type: 'string'}
                                    ,{name: 'start', type: 'string' }
                                    ,{name: 'stop', type: 'string' }
                                    ,{name: 'day', type:'date', dateFormat:'timestamp'}
                                    ,{name: 'description', type: 'string'}
                                    ,{name: 'video', type: 'string'}
                                    ,{name: 'audio', type: 'string'}
                                    ,{name: 'vps', type:'date', dateFormat:'timestamp'}
                                    ,{name: 'timerid', type: 'string'}
                                    ,{name: 'timeractiv', type: 'string'}
                                    ,{name: 'running', type: 'string'}
                                  ]
                      }),
            proxy : new Ext.data.HttpProxy({
                url: XXV.help.baseURL()
                ,method: 'GET'
            }),
            sortInfo:{field:'day', direction:'ASC'},
            groupField:'day'
    });
}

Ext.xxv.programGrid = function(viewer, record) {
    this.viewer = viewer;
    this.preview = new Ext.xxv.programPreview(viewer);
    //Ext.apply(this, config);

    // create the data store
    this.store = new Ext.xxv.programStore(record);
    this.store.setDefaultSort('day', "ASC");

    this.columns = [{
           header: this.szColTitle,
           dataIndex: 'title',
           width: 150,
           renderer: this.formatTitle
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
    }];

    var cm = new Ext.grid.ColumnModel(this.columns);
    cm.defaultSortable = true;

    Ext.xxv.programGrid.superclass.constructor.call(this, {
        region: 'center'
        ,id: 'program-grid'
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
            pageSize: configuration.pageSize,
            store: this.store,
            displayInfo: true
        })

        ,plugins:[new Ext.ux.grid.Search({
             position:'top'
            ,emptyText:'Search ...'
            ,paramNames: {
                     fields:'cmd'
                    ,all:'p'
                    ,cmd:'p'
                    ,query:'filter'
                }
        })]
    });

    this.store.on({
         'load' :          this.onLoad
        ,'beforeload'    : this.onBeforeLoad
        ,'loadexception' : this.onLoadException
        ,scope:this
    });
    this.on('rowcontextmenu', this.onContextClick, this);
    this.getSelectionModel().on('rowselect', this.preview.select, this.preview, {buffer:50});
};

Ext.extend(Ext.xxv.programGrid, Ext.grid.GridPanel, {

     szTitle         : "Program guide"
    ,szFindReRun     : "Find rerun"
    ,szRecord        : "Record"
    ,szColTitle      : "Title"
    ,szColDay        : "Day"
    ,szColStart      : "Start"
    ,szColStop       : "Stop"
    ,szColDayFormat  : "l, m/d/Y"
    ,szLoadException : "Couldn't get program data!\r\n{0}"

    ,stateful:  true

    ,onLoadException :  function( scope, o, arg, e) {
      new Ext.xxv.MessageBox().msgFailure(this.szLoadException, e);
    }
    ,onBeforeLoad : function(  store, opt ) {
      this.preview.clear();
    }
    ,onLoad : function( store, records, opt ) {
      this.getSelectionModel().selectFirstRow();
      this.ownerCt.SetPanelTitle(store.title);
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
                    }
                   ,{
                    text: this.szRecord,
                    iconCls: 'record-icon',
                    scope:this,
                    handler: function(){ this.viewer.Record(this.ctxRecord); }
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

    ,reload : function(data) {
        this.store.baseParams = {
             cmd: 'p'
            ,data: data.position
        };
        this.store.title = data.name;
        this.store.load({params:{start:0, limit:configuration.pageSize}});
    }
    ,formatTitle: function(value, p, record) {
        return String.format(
                '<div class="topic"><b>{0}</b> <span class="subtitle">{1}</span></div>',
                value, record.data.subtitle
                );
    }
});

Ext.xxv.programPreview = function(viewer) {
    this.viewer = viewer;
    Ext.xxv.programPreview.superclass.constructor.call(this, {
        id: 'program-preview',
        region: 'south',
        cls:'preview',
        autoScroll: true,
        stateful:true,
        tbar: [ {
            id:'s',
            text: this.szFindReRun,
            iconCls: 'find-icon',
            disabled:true,
            scope: this.viewer,
            handler: function(){ this.searchTab(this.gridProgram.getSelectionModel().getSelected()); }
        } ,{
            id:'tn',
            text: this.szRecord,
            iconCls: 'record-icon',
            disabled:true,
            scope: this.viewer,
            handler: function(){ this.Record(this.gridProgram.getSelectionModel().getSelected()); }
        } ]
    });
};

Ext.extend(Ext.xxv.programPreview, Ext.Panel, {

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

function createProgramView(viewer,id, record) {

    viewer.gridProgram = new Ext.xxv.programGrid(viewer, record);

    var tab = new Ext.xxv.Panel({
            id:id,
            iconCls: 'channel-icon',
            layout:'border',
            stateful:true,
            hideMode:'offsets',
            closable:true,
            items:[
                viewer.gridProgram,
            {
                id:'program-bottom-preview',
                layout:'fit',
                items:XXV.BottomPreview ? 0 : viewer.gridProgram.preview,
                height: 250,
                split: true,
                border:false,
                region:'south',
                hidden:XXV.BottomPreview
            }, {
                id:'program-right-preview',
                layout:'fit',
                items:XXV.RightPreview ? 0 : viewer.gridProgram.preview,
                border:false,
                region:'east',
                width:350,
                split: true,
                hidden:XXV.RightPreview
            }]
    });

    viewer.add(tab);
    return tab;
}
