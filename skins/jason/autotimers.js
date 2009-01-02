/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.autotimerStore = function() {

    // create the data store
    return new Ext.data.Store({
             baseParams:{cmd:'al'}
            ,autoLoad:{params:{start:0, limit:configuration.pageSize}}
            ,reader: new Ext.xxv.jsonReader({
                    fields: [
                      {name: 'id', type: 'int'},
                      {name: 'active', type: 'int', convert: function(x) { if(x == 'y'){ return 1;} else {return 0;} }},
                      {name: 'title', type: 'string'},
                      {name: 'channels', type: 'string'},
                      {name: 'directory', type: 'string'},
                      {name: 'start', type: 'string'},
                      {name: 'stop', type: 'string'},
                      {name: 'minlength', type: 'int'}
                    ]
                })
            ,proxy : new Ext.data.HttpProxy({
                 url: XXV.help.baseURL()
                ,method: 'GET'
            })
            ,sortInfo:{field:'title', direction:'ASC'}
    });
};

Ext.xxv.autotimerGrid = function(viewer, channels) {
    this.viewer = viewer;
    //Ext.apply(this, {}); // Apply config

    // create the data store
    this.store = new Ext.xxv.autotimerStore();
    this.store.setDefaultSort('title', "ASC");

    // custom columns as plugins
    this.activeColumn = new Ext.grid.CheckColumn({
       header: this.szColActive
       ,dataIndex: 'active'
       ,width: 50
       ,bitmask: 1
       ,editable: false
       ,hidden: true
    });

    this.columns = [
        {
           header: this.szColSearch
           ,dataIndex: 'title'
           ,width: 200
           ,renderer: this.formatTitle
        },
        this.activeColumn,
        {           header: this.szColChannels
           ,dataIndex: 'channels'
           ,width: 130
        },{
           header: this.szColDirectory
           ,dataIndex: 'directory'
           ,width: 200
        },{
           header: this.szColStart
           ,dataIndex: 'start'
           ,width: 50
        },{
           header: this.szColStop
           ,dataIndex: 'stop'
           ,width: 50
        },{
           header: this.szColMinLength
           ,dataIndex: 'minlength'
           ,width: 50
        }
    ];

    var cm = new Ext.grid.ColumnModel(this.columns);
    cm.defaultSortable = true;

    Ext.xxv.autotimerGrid.superclass.constructor.call(this, {
         region: 'center'
        ,id: 'autotimer-view-grid'
        ,loadMask: true
        ,plugins:[this.activeColumn]
        ,clicksToEdit:1
        ,cm: cm
        ,sm: new Ext.grid.RowSelectionModel({
            singleSelect:false
        })
        ,tbar:new Ext.PagingToolbar({
              pageSize: this.store.autoLoad.params.limit
              ,store: this.store
              ,displayInfo: true 
              ,items: [
              {
                   id:'an'
                  ,iconCls: 'new-icon'
//                ,text: this.szNew
                  ,scope: this
                  ,disabled:false
                  ,handler: function(){ this.EditItem(null); }
              }
              ]})
              ,plugins:[new Ext.ux.grid.Search({
                   position:'top'
                  ,shortcutKey:null
                  ,paramNames: {
                          fields:'cmd'
                          ,all:'al'
                          ,cmd:'ase'
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

Ext.extend(Ext.xxv.autotimerGrid,  Ext.grid.EditorGridPanel, {

     szTitle         : "Search timer"
    ,szFindReRun     : "Find rerun"
    ,szNew           : "New"
    ,szEdit          : "Edit"
    ,szDelete        : "Delete"
    ,szColSearch     : "Search text"
    ,szColActive     : "Active"
    ,szColChannels   : "Channels"
    ,szColDirectory  : "Directory"
    ,szColStart      : "Start"
    ,szColStop       : "Stop"
    ,szColMinLength  : "Min. Length"
    ,szLoadException : "Couldn't get data about autotimer!\r\n{0}"
    ,szDeleteSuccess : "Autotimer deleted successful.\r\n{0}"
    ,szDeleteFailure : "Couldn't delete autotimer!\r\n{0}"
 
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
                     id:'ae'
                    ,text:  this.szEdit
                    ,iconCls: 'edit-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function() { this.EditItem(this.ctxRecord); }
                   },{
                     id:'ad'
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
    }
    ,onContextHide : function(){
        if(this.ctxRow){
            Ext.fly(this.ctxRow).removeClass('x-node-ctx');
            this.ctxRow = null;
        }
    }
    ,formatTitle: function(value, p, record) {
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
            sel.reverse();
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
         ,url: XXV.help.cmdAJAX('ad')
         ,timeout: 15000
         ,success: this.onDeleteSuccess
         ,failure: this.onDeleteFailure
         ,params:{ data: todel }
      });
    }

  /******************************************************************************/
    ,EditItem : function( record ) {
      this.stopEditing();
      var item;

      if(record != null) {
        var gsmTimer = this.getSelectionModel();
        gsmTimer.selectRecords([record]);

        item = {
           cmd:   'ae'
          ,id:    record.data.id
          ,title: record.data.title
        };
      } else {
        item = {
           cmd:   'an'
          ,id:    0
          ,title: this.szNew
        };
      }

      if(this.viewer.formwin){
        this.viewer.formwin.close();
      }
      this.viewer.formwin = new Ext.xxv.Question(item,this.store);
    },
    onEditItem : function(grid, index, e) {
      e.stopEvent();
      if(this.ctxRow){
          Ext.fly(this.ctxRow).removeClass('x-node-ctx');
          this.ctxRow = null;
      }
      var record = this.store.getAt(index);
      this.EditItem(record);
    }
});

function createAutoTimerView(viewer,id) {

    viewer.gridAutoTimer = new Ext.xxv.autotimerGrid(viewer, viewer.storeChannels);
  
    tab = new Ext.xxv.Panel({
      id: id,
      iconCls:"autotimer-icon",
      closable:true,
      border:false,
      layout:'border',
      stateful:true,
      hideMode:'offsets',
      items:[
            viewer.gridAutoTimer
            ]
    });

    viewer.add(tab);
    return tab;
}

