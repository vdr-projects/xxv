/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.musicStore = function() {

    // create the data store
    return new Ext.data.GroupingStore({
             baseParams:{cmd:'ml'}
            ,autoLoad:{params:{start:0, limit:configuration.pageSize}}
            ,reader: new Ext.xxv.jsonReader({
                    fields: [
                       {name: 'id', type: 'string'}
                      ,{name: 'artist', type: 'string'}
                      ,{name: 'album', type: 'string'}
                      ,{name: 'title', type: 'string'}
                      ,{name: 'track', type: 'string'}
                      ,{name: 'year', type: 'string'}
                      ,{name: 'duration', type: 'string'}
                      ,{name: 'genre', type: 'string'}
                      ,{name: 'comment', type: 'string'}
                    ]
                })
            ,proxy : new Ext.data.HttpProxy({
                 url: XXV.help.baseURL()
                ,method: 'GET'
            })
            ,sortInfo:{field:'track', direction:'ASC'}
            ,groupField:'album'
    });
};

Ext.xxv.musicGrid = function(viewer) {
    this.viewer = viewer;
    //Ext.apply(this, {}); // Apply config

    // create the data store
    this.store = new Ext.xxv.musicStore();
    this.store.setDefaultSort('track', "ASC");

    this.columns = [
        {
            header: this.szColArtist
           ,dataIndex: 'artist'
           ,width: 200
        },{
            header: this.szColTitle
           ,dataIndex: 'title'
           ,width: 200
           ,id:'expand'
        },{
            header: this.szColAlbum
           ,dataIndex: 'album'
           ,width: 200
           ,hidden: true
        },{
            header: this.szColTrack
           ,dataIndex: 'track'
           ,width: 50
           ,hidden: true
        },{
            header: this.szColYear
           ,dataIndex: 'year'
           ,width: 50
           ,hidden: true
        },{
            header: this.szColDuration
           ,dataIndex: 'duration'
           ,width: 50
        },{
            header: this.szColGenre
           ,dataIndex: 'genre'
           ,width: 100
           ,hidden: true
        },{
            header: this.szColComment
           ,dataIndex: 'comment'
           ,width: 250
           ,hidden: true
        }
    ];

    var cm = new Ext.grid.ColumnModel(this.columns);
    cm.defaultSortable = true;

    Ext.xxv.musicGrid.superclass.constructor.call(this, {
         region: 'center'
        ,id: 'music-view-grid'
        ,loadMask: true
        ,clicksToEdit:1
        ,autoExpandColumn:'expand'
        ,cm: cm
        ,sm: new Ext.grid.RowSelectionModel({
            singleSelect:false
        })
        ,view: new Ext.grid.GroupingView({
            enableGroupingMenu:false,
            showGroupName: false
        })
        ,tbar:new Ext.PagingToolbar({
              pageSize: this.store.autoLoad.params.limit
              ,store: this.store
              ,displayInfo: true 
              /*,items: [
              {
                   id:'mn'
                  ,iconCls: 'music-new-icon'
                  ,tooltip: this.szNew
                  ,scope: this
                  ,disabled:false
                  ,handler: function(){ this.EditItem(null); }
              }
              ]*/})
        ,plugins:[new Ext.ux.grid.Search({
             position:'top'
            ,shortcutKey:null
            ,paramNames: {
                    fields:'cmd'
                    ,all:'ml'
                    ,cmd:'ms'
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
    //this.on('rowdblclick', this.onEditItem, this);
};

Ext.extend(Ext.xxv.musicGrid,  Ext.grid.GridPanel, { // Ext.grid.EditorGridPanel

     szTitle         : "Music"
    ,szToolTip       : "Display list of music title"
    ,szFindTitle     : "Search title"
    ,szPlaying       : "Playing"
    ,szColAlbum	     : "Album"
    ,szColArtist     : "Artist"
    ,szColTitle      : "Title"
    ,szColDuration   : "Duration"
    ,szColTrack      : "Track"
    ,szColYear       : "Year"
    ,szColGenre      : "Genre"
    ,szColComment    : "Comment"
    ,szLoadException : "Couldn't get title from music list!\r\n{0}"
 
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
                items: [/*{
                     id:'s'
                    ,text:  this.szFindTitle
                    ,iconCls: 'find-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function(){ this.viewer.searchTab(this.ctxRecord);}
                   },*/{
                     id:'m3'
                    ,text:  this.szPlaying
                    ,iconCls: 'playing-music-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function() { this.PlayingItem(this.ctxRecord); }
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
    ,PlayingItem : function( record ) {
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

			var item = {
			   url  : XXV.help.cmdHTML('m3',{data:todel})
			  ,title: sel[0].data.title
			};

			if(!this.viewer.streamwin){
			  this.viewer.streamwin = new Ext.xxv.StreamWindow(item);
			} else {
			  this.viewer.streamwin.show(item);
			}
      this.loadMask.hide(); 
    }
});

function createMusicView(viewer,id) {

    viewer.musicGrid = new Ext.xxv.musicGrid(viewer);
  
    tab = new Ext.xxv.Panel({
      id: id,
      iconCls:"music-icon",
      closable:true,
      border:false,
      layout:'border',
      stateful:true,
      hideMode:'offsets',
      items:[ viewer.musicGrid ]
    });


    viewer.add(tab);
    return tab;
}

