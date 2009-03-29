/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.MainSearchField = Ext.extend(Ext.form.TwinTriggerField, {
    initComponent : function(){
  		Ext.xxv.MainSearchField.superclass.initComponent.call(this);
  	  	this.on('specialkey', function(f, e){
            if(e.getKey() == e.ENTER){
                this.onTrigger2Click();
            }
        }, this);
    }
    ,emptyText:'Search ...'
    ,validationEvent:false
    ,validateOnBlur:false
    //,trigger1Class:'x-form-clear-trigger'
    ,trigger2Class:'x-form-search-trigger'
    ,hideTrigger1:true
    ,width:200
    ,hasSearch : false

    /*,onTrigger1Click : function(){
       if(this.hasSearch){
        this.hasSearch = false;
        this.setValue();
       }
    }*/
});

Ext.xxv.MainMenu = function(/*config*/){

    var selTheme = this.initTheme();

    XXV.configMenu = new Ext.menu.Menu();
    var setupMenu = new Ext.menu.Menu(
    {
      items:[
        {
	          text:this.szOwnSettings
           ,iconCls: 'setup-icon'
           ,disabled: false
           ,handler: XXV.help.Settings
           ,scope:XXV.help
        },{
	          text:this.szGlobalSettings
           ,iconCls: 'setup-icon'
           ,menu: XXV.configMenu
        },'-',{
          text: Ext.xxv.movetimersGrid.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('mtl'); },
          iconCls:"movetimers-icon"
        },{   
          text: Ext.xxv.vdrGrid.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('vl'); },
          iconCls:"vdr-icon"
        },{   
          text: Ext.xxv.usersGrid.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('ul'); },
          iconCls:"users-icon"
        }
       ]
    });

    var systemMenu = new Ext.menu.Menu(
    {
      items:[
        {
	          text:this.szMenuItemSetup
           ,iconCls: 'setup-icon'
           ,menu: setupMenu
        },'-',{
           text:this.szMenuItemLogout
       	  ,handler: this.Logout
          ,iconCls:"logout-icon"
          ,disabled:false
        }
       ]
    });



    var ProgrammingMenu = new Ext.menu.Menu(
    {
      items:[
        {
          text: Ext.xxv.autotimerGrid.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('al'); },
          iconCls:"autotimer-icon"
        }, 
        {
          text: Ext.xxv.timerGrid.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('tl'); },
          iconCls:"timer-icon"
        }
       ]
    });
    
    var MediaMenu = new Ext.menu.Menu(
    {
      items:[
        {
          text: Ext.xxv.recordingsDataView.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('rl'); },
          iconCls:"recordings-icon"
        }
        ,{
          text: Ext.xxv.chronicleGrid.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('chrl'); },
          iconCls:"chronicle-icon"
        },{
          text: Ext.xxv.musicGrid.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('ml'); },
          iconCls:"music-icon",
        }/*,{
          text: Ext.xxv.mediaDataView.prototype.szTitle, 
          handler: function() { XXV.tab.openTab('mll'); },
          iconCls:"media-icon",
          disabled:true
        }*/
       ]
    });

    var RemoteMenu = new Ext.menu.Menu(
    {
      items:[
        {
          text: Ext.xxv.RemoteWindow.prototype.szTitle, 
          handler: function() { Ext.xxv.RemoteWindowOpen(); },
          iconCls:"remote-icon"
        }
        ,{
          text: Ext.xxv.MonitorWindow.prototype.szTitle, 
          handler: function() { Ext.xxv.MonitorWindowOpen(); },
          iconCls:"monitor-icon"
        }
       ]
    });
    // see this.styles to enum themes
    var themes = new Array;
    for(var i = 0, len = this.styles.length; i < len; i++){
	    themes.push({
	    text: this.styles[i][1],
	    checked: selTheme == i ? true : false,
	    group: 'theme',
	    checkHandler: this.onSelectTheme,
	    scope: this
	    });
    }

    Ext.xxv.MainMenu.superclass.constructor.call(this, {
      id:"MainMenu",
      region:"north",
      height:26, 
      items:[
          { text:this.szMenuXXV,
            menu:systemMenu,      
            iconCls:"xxv-icon" 
          },
          { text:this.szMenuProgramming, 
            menu:ProgrammingMenu, 
            iconCls:"edit-icon" 
          },
          { text:this.szMenuMedia,       
            menu:MediaMenu,       
            iconCls:"media-icon"  
          },
          { text:this.szMenuRemote,       
            menu:RemoteMenu,       
            iconCls:"remote-icon"  
          },
          {   text:this.szMenuView,
              iconCls: 'view-icon',
              menu:{
                  items: [
                            {
                              text: this.szSelectTheme,
                              iconCls: 'preview-hide',
                              menu: {
                                  cls:'reading-menu',
                                  items: themes
                              }
                          }
                          ,
                          {   text:this.szPreviewPreviewPane,
                              iconCls: 'preview-icon',
                              menu:{
                                  id:'reading-menu',
                                  cls:'reading-menu',
                                  items: [
                                  {
                                      text:this.szPreviewBottom,
                                      checked:true,
                                      group:'rp-group',
                                      checkHandler:XXV.tab.movePreview,
                                      scope:XXV.tab,
                                      iconCls:'preview-bottom'
                                  },{
                                      text:this.szPreviewRight,
                                      checked:false,
                                      group:'rp-group',
                                      checkHandler:XXV.tab.movePreview,
                                      scope:XXV.tab,
                                      iconCls:'preview-right'
                                  },{
                                      text:this.szPreviewHide,
                                      checked:false,
                                      group:'rp-group',
                                      checkHandler:XXV.tab.movePreview,
                                      scope:XXV.tab,
                                      iconCls:'preview-hide'
                                  }]
                              }
                          }
                      ]}
          },
          "->", 
          new Ext.xxv.MainSearchField({   
                onTrigger2Click : function(){
                        var v = this.getRawValue();
                        if(v.length < 1){
                            this.onTrigger1Click();
                            return;
                        }
                        XXV.tab.openSearch(v);
                }
              })
        ]
    });
};


Ext.extend(Ext.xxv.MainMenu, Ext.Toolbar, {

     szMenuXXV             : 'XXV'
    ,szMenuProgramming     : 'Programming'
    ,szMenuMedia           : 'Media'
    ,szMenuRemote          : 'Remote access'
    ,szMenuView            : 'View'

    ,szMenuItemSetup       : 'Setup'
    ,szGlobalSettings      : 'Global settings'
    ,szOwnSettings         : 'Own settings'
    ,szMenuItemLogout	     : 'Logout'    
    ,szMenuItemLogoutTooltip : 'Click this button to logout from XXV'

    ,szSelectTheme         : 'Select theme'
    ,szPreviewPreviewPane  : 'Preview Pane'
    ,szPreviewRight        : 'Right'
    ,szPreviewBottom       : 'Bottom'
    ,szPreviewHide         : 'Hide'

    ,szLogoutSuccess : "Successful logout.\r\n{0}"
    ,szLogoutFailure : "Couldn't logout!\r\n{0}"

    ,cssPath:'extjs/resources/css/'
    ,styles: [
               ['xtheme-default.css',   'Default Theme']
              ,['xtheme-gray.css',      'Gray']
              ,['xtheme-slate.css',     'Slate']
              ,['xtheme-darkgray.css',  'Dark Gray']
              ,['xtheme-black.css',     'Black']
              ,['xtheme-olive.css',     'Olive']
              ,['xtheme-purple.css',    'Purple']
          ]
    ,initTheme: function(){
        if(Ext.state.Manager.getProvider()) {
            var theme = Ext.state.Manager.get('theme');
            if(theme && theme != 'xtheme-default.css') {
                for(var i = 0, len = this.styles.length; i < len; i++){
                if(this.styles[i][0] == theme) {
                  Ext.util.CSS.swapStyleSheet('theme', this.cssPath + theme);
                  return i;
                }
              }
            }
        }
        return 0;
    }
    ,onSelectTheme: function(item, checked){
        if(checked) {
          for(var i = 0, len = this.styles.length; i < len; i++){
          if(this.styles[i][1] == item.text) {
            var theme = this.styles[i][0];
              Ext.util.CSS.swapStyleSheet('theme', this.cssPath + theme);

            if(Ext.state.Manager.getProvider()) {
                Ext.state.Manager.set('theme', theme);
            }
            return;
          }
        }
       }
    }
/******************************************************************************/
    ,Logout: function(){
        Ext.MessageBox.show({
                   title: 'Logout',
                   msg: 'Please wait...',
                   width:240,
                   closable:false,
               });
      Ext.Ajax.request({
          url: XXV.help.cmdAJAX('logout')
      });
	    setTimeout(function(){
            XXV.viewport.container.fadeOut(
              {
                  remove:true,
                  duration: .5, 
                  callback:function(){
                    Ext.MessageBox.updateText('Session closed!');
                  }
              }
            );
      }, 250);
    }
});


