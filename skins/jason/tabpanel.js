/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.tabPanel = function(){

    this.initPreview();
    var tab = creatNowView(this,'n');

    Ext.xxv.tabPanel.superclass.constructor.call(this, {
        id:'main-tabs',
        activeTab:0,
        region:'center',
        margins:'0 5 5 0',
        resizeTabs:true,
        tabWidth:150,
        minTabWidth: 120,
        enableTabScroll: true,
        plugins: new Ext.ux.TabCloseMenu(),
        items: tab
    });

};

Ext.extend(Ext.xxv.tabPanel, Ext.TabPanel, {

    initPreview : function(){
      XXV.BottomPreview = false;
      XXV.RightPreview = true;
      if(Ext.state.Manager.getProvider()) {
        var previewstate = Ext.state.Manager.get('preview-layout');
        if(previewstate) {
          switch(previewstate){
            case 'preview-bottom':
                XXV.BottomPreview = false;
                XXV.RightPreview = true;
                break;
            case 'preview-right':
                XXV.BottomPreview = true;
                XXV.RightPreview = false;
                break;
            case 'preview-hide':
                XXV.BottomPreview = true;
                XXV.RightPreview = true;
                break;
            }
          }
      }
    }
    ,movePreview : function(m, pressed){
        if(!m || m.group != 'rp-group'){ 
            return;
        }
        if(pressed){
            var pages = ['now','program','timer','search','recording'];
            for(var i = 0, len = pages.length; i < len; i++){
                var page = pages[i];
                var right = Ext.getCmp(page + '-right-preview');
                var bot = Ext.getCmp(page + '-bottom-preview');
                if(right && bot) {
                  var preview;
                  if(page == 'now') {
                    preview  = this.gridNow.preview;
                  } else if(page == 'program') {
                    preview  = this.gridProgram.preview;
                  } else if(page == 'timer') {
                    preview  = this.gridTimer.preview;
                  } else if(page == 'search') {
                    preview  = this.gridSearch.preview;
                  } else if(page == 'recording') {
                    preview  = this.gridRecordings.preview;
                  } else {
                    continue;
                  }
                  switch(m.iconCls){
                    case 'preview-bottom':
                        right.hide();
                        bot.add(preview);
                        bot.show();
                        bot.ownerCt.doLayout();
                        XXV.BottomPreview = false;
                        XXV.RightPreview = true;
                        //btn.setIconClass('preview-bottom');
                        break;
                    case 'preview-right':
                        bot.hide();
                        right.add(preview);
                        right.show();
                        right.ownerCt.doLayout();
                        XXV.BottomPreview = true;
                        XXV.RightPreview = false;
                        //btn.setIconClass('preview-right');
                        break;
                    case 'preview-hide':
                        preview.ownerCt.hide();
                        right.hide();
                        bot.hide();
                        preview.ownerCt.ownerCt.doLayout();
                        XXV.BottomPreview = true;
                        XXV.RightPreview = true;
                        //btn.setIconClass('preview-hide');
                        break;
                    }
                }
            }
            if(Ext.state.Manager.getProvider()) {
                Ext.state.Manager.set('preview-layout', m.iconCls);
            }
        }
    }
    ,openNow : function(){
          var id = 'n';
          var tab;
          if(!(tab = this.getItem(id))){
            tab = creatNowView(this,'n');
          } else {
            tab.LoadTitle();
            this.gridNow.reload();
          }
          this.setActiveTab(tab);
    }
    ,openProgram : function(data){
          var id = 'p';
          var tab;
          if(!(tab = this.getItem(id))){
            tab = createProgramView(this,id,data);
          } else {
            tab.LoadTitle();
            this.gridProgram.reload(data);
          }
          this.setActiveTab(tab);
    }
    ,openAutoTimer : function(){
        var id = 'al';
        var tab;
        if(!(tab = this.getItem(id))){
          tab = createAutoTimerView(this,id);
        }
        this.setActiveTab(tab);
    }
    ,openTimer : function(){
        var id = 'tl';
        var tab;
        if(!(tab = this.getItem(id))){
          tab = createTimerView(this,id);
        }
        this.setActiveTab(tab);
    }
    ,openRecordings : function(){
        var id = 'rl';
        var tab;
        if(!(tab = this.getItem(id))){
          tab = createRecordingsView(this,id);
        }
        this.setActiveTab(tab);
    }
    ,openChronicle : function(){
        var id = 'chrl';
        var tab;
        if(!(tab = this.getItem(id))){
          tab = createChronicleView(this,id);
        }
        this.setActiveTab(tab);
    }
    ,openSearch : function(lookup){
        var id = 's';
        var tab;
        if(!(tab = this.getItem(id))){
          tab = createSearchView(this,id,lookup);
        }else {
          tab.LoadTitle();
          this.gridSearch.loadSearch(lookup);
        }
        this.setActiveTab(tab);
    }
    ,searchTab : function(record){
        if(!record || !record.data) return;
        var d = record.data;
        var Woerter = d.title.split("~");
        var title = Woerter[0];
        return this.openSearch(title);
    }
    ,Record : function(record){
        if(!record || !record.data) return;
        this.gridNow.Record(record);
    }
    ,RecordID : function(id){
        if(!id) return;
        this.gridNow.RecordID(id);
    }
    ,openVDRList : function(){
        var id = 'vl';
        var tab;
        if(!(tab = this.getItem(id))){
          tab = createVDRView(this,id);
        }
        this.setActiveTab(tab);
    }
    ,openUsersList : function(){
        var id = 'ul';
        var tab;
        if(!(tab = this.getItem(id))){
          tab = createUsersView(this,id);
        }
        this.setActiveTab(tab);
    }
});
