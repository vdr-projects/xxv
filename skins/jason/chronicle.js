/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.chronicleStore = function() {

    // create the data store
    return new Ext.data.Store({
             baseParams:{cmd:'chrl'}
            ,autoLoad:{params:{start:0, limit:configuration.pageSize}}
            ,reader: new Ext.xxv.jsonReader({
                    fields: [
                      {name: 'id', type: 'int'},
                      {name: 'title', type: 'string'},
                      {name: 'channels', type: 'string'},
                      {name: 'day', type:'date', dateFormat:'timestamp'},
                      {name: 'start', type: 'string'},
                      {name: 'stop', type: 'string'}
                    ]
                })
            ,proxy : new Ext.data.HttpProxy({
                 url: XXV.help.baseURL()
                ,method: 'GET'
            })
            ,sortInfo:{field:'day', direction:'ASC'}
    });
};

Ext.xxv.chronicleGrid = function(viewer, channels) {
    this.viewer = viewer;

    // create the data store
    this.store = new Ext.xxv.chronicleStore();
    this.store.setDefaultSort('title', "ASC");

    this.columns = [
        {
           id:'expand'
           ,header: this.szColTitle
           ,dataIndex: 'title'
           ,width: 200
           ,renderer: this.formatTitle
        },
        {           header: this.szColChannel
           ,dataIndex: 'channels'
           ,width: 130
        },{
           header: this.szColDay
           ,dataIndex: 'day'
           ,width: 50
           ,renderer: Ext.util.Format.dateRenderer(this.szColDayFormat)
        },{
           header: this.szColStart
           ,dataIndex: 'start'
           ,width: 50
        },{
           header: this.szColStop
           ,dataIndex: 'stop'
           ,width: 50
        }
    ];

    var cm = new Ext.grid.ColumnModel(this.columns);
    cm.defaultSortable = true;

    Ext.xxv.chronicleGrid.superclass.constructor.call(this, {
         region: 'center'
        ,id: 'chronicle-view-grid'
        ,loadMask: true
        ,clicksToEdit:1
        ,autoExpandColumn:'expand'
        ,cm: cm
        ,sm: new Ext.grid.RowSelectionModel({
            singleSelect:false
        })
        ,tbar:new Ext.PagingToolbar({
              pageSize: this.store.autoLoad.params.limit,
              store: this.store,
              displayInfo: true })
        ,plugins:[new Ext.ux.grid.Search({
             position:'top'
            ,shortcutKey:null
            ,paramNames: {
                    fields:'cmd'
                    ,all:'chrl'
                    ,cmd:'chrs'
                    ,query:'data'
                }
        })]
    });

    this.store.on({
         'load' : this.onLoad
        ,'loadexception' : this.onLoadException
        ,scope:this
    });

    this.on('rowcontextmenu', this.onContextClick, this);
    this.on('rowdblclick', this.onEditItem, this);
};

Ext.extend(Ext.xxv.chronicleGrid,  Ext.grid.EditorGridPanel, {

     szTitle         : "Chronicle"
    ,szToolTip       : "Display recordings in chronological order"
    ,szFindReRun     : "Find rerun"
    ,szDelete        : "Delete"
    ,szColTitle      : "Title"
    ,szColDay        : "Day"
    ,szColChannel    : "Channel"
    ,szColStart      : "Start"
    ,szColStop       : "Stop"
    ,szColDayFormat  : "l, m/d/Y"
    ,szLoadException : "Couldn't get data from chronicle!\r\n{0}"
    ,szDeleteSuccess : "Data from chronicle deleted successful.\r\n{0}"
    ,szDeleteFailure : "Couldn't delete data from chronicle!\r\n{0}"
 
    ,stateful:  true

    ,onLoadException :  function( scope, o, arg, e) {
      new Ext.xxv.MessageBox().msgFailure(this.szLoadException, e);
    }
    ,onLoad : function( store, records, opt ) {
      this.getSelectionModel().selectFirstRow();
      this.ownerCt.SetPanelTitle(this.szTitle);
    }
    ,onContextClick : function(grid, index, e){
        if(!this.menu){ // create context menu on first right click
            this.menu = new Ext.menu.Menu({
                id:'grid-ctx',
                items: [{
                     id:'s'
                    ,text:  this.szFindReRun
                    ,iconCls: 'find-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function(){ this.viewer.searchTab(this.ctxRecord);}
                   },{
                     id:'chrd'
                    ,text:  this.szDelete
                    ,iconCls: 'delete-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function() { this.DeleteItem(this.ctxRecord); }
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

        var items = this.menu.items;
        if(items) { items.eachKey(function(key, f) {
                                  if(XXV.help.cmdAllowed(key)) f.enable();
                      },items); }

        this.menu.showAt(e.getXY());
    },

    onContextHide : function(){
        if(this.ctxRow){
            Ext.fly(this.ctxRow).removeClass('x-node-ctx');
            this.ctxRow = null;
        }
    },

    formatTitle: function(value, p, record) {
        return String.format(
              '<div class="topic"><b>{0}</b></div>',
              value
              );
    }
  /******************************************************************************/
    ,onDeleteSuccess : function( response,options ) 
    { 
        this.loadMask.hide(); 

        var o = eval("("+response.responseText+")");

        if(o && o.data && typeof(o.data) == 'string' 
             && o.param && o.param.state && o.param.state == 'success') {
            new Ext.xxv.MessageBox().msgSuccess(this.szDeleteSuccess, o.data);

            var gsm = this.getSelectionModel();
      	    var sel = options.params.data.split(",");
            sel.sort(function (a, b) { return b - a; });
            for(var i = 0, len = sel.length; i < len; i++){
              if(gsm.isIdSelected(sel[i])) {
                if(gsm.hasPrevious()) {
                  gsm.selectPrevious();
                } else {
                  gsm.selectNext();
                }
              }
              var record = this.store.getById(sel[i]);
              this.store.remove(record);
            }
        } else {
            var msg = '';
            if(o && o.data && typeof(o.data) == 'string') {
              msg = o.data;
            }
            new Ext.xxv.MessageBox().msgFailure(this.szDeleteFailure, msg);
        }
    }

    ,onDeleteFailure : function( response,options ) 
    { 
        this.loadMask.hide(); 
        new Ext.xxv.MessageBox().msgFailure(this.szDeleteFailure, response.statusText);
    }

    ,DeleteItem : function( record ) {
      this.stopEditing();
      this.loadMask.show(); 

      var gsm = this.getSelectionModel();
      var sel = gsm.getSelections()
      if(sel.length <= 0) {
       gsm.selectRecords([record]);
       sel.push(record);
      }
      var todel = "";
      for(var i = 0, len = sel.length; i < len; i++){
        if(i != 0)
   	      todel += ',';
	      todel += sel[i].data.id;
      }
      Ext.Ajax.request({
          scope: this
         ,url: XXV.help.cmdAJAX('chrd')
         ,timeout: 15000
         ,success: this.onDeleteSuccess
         ,failure: this.onDeleteFailure
         ,params:{ data: todel }
      });
    }
});

function createChronicleView(viewer,id) {

    viewer.chronicleGrid = new Ext.xxv.chronicleGrid(viewer, viewer.storeChannels);
  
    tab = new Ext.xxv.Panel({
      id: id,
      iconCls:"chronicle-icon",
      closable:true,
      border:false,
      layout:'border',
      stateful:true,
      hideMode:'offsets',
      items:[ viewer.chronicleGrid ]
    });


    viewer.add(tab);
    return tab;
}

