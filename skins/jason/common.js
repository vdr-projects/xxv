/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.grid.CheckColumn = function(config){
    this.editable = true;
    Ext.apply(this, config);
    if(!this.id){
        this.id = Ext.id();
    }
    this.renderer = this.renderer.createDelegate(this);
};

Ext.grid.CheckColumn.prototype ={
    init : function(grid){
        this.grid = grid;
        this.grid.on('render', function(){
            var view = this.grid.getView();
            if(this.editable)
              view.mainBody.on('mousedown', this.onMouseDown, this);
        }, this);
    },

    onMouseDown : function(e, t){
        if(t.className && t.className.indexOf('x-grid3-cc-'+this.id) != -1){
            e.stopEvent();
            var index = this.grid.getView().findRowIndex(t);
            var record = this.grid.store.getAt(index);
            var flags = record.data[this.dataIndex];
            if(flags & this.bitmask) {
              flags &= ~(this.bitmask);
            } else {
              flags |= (this.bitmask);
            }
            record.set(this.dataIndex, flags);
        }
    },

    renderer : function(v, p, record){
        p.css += ' x-grid3-check-col-td'; 
        return '<div class="x-grid3-check-col'+((v&(this.bitmask))?'-on':'')+' x-grid3-cc-'+this.id+'">&#160;</div>';
    }
};

Ext.namespace('Ext.xxv');
/******************************************************************************/
Ext.xxv.MessageBox = function(config){
    Ext.apply(this, config);
    if(!this.id){
        this.id = Ext.id();
    }
};

Ext.xxv.MessageBox.prototype = {

         szFailure : "Failure!"
        ,szSuccess : "Success!"

        ,msgFailure : function(format){ this.msg(this.szFailure,format, Array.prototype.slice.call(arguments, 1)); }
        ,msgSuccess : function(format){ this.msg(this.szSuccess,format, Array.prototype.slice.call(arguments, 1)); }
        ,msg : function(title,format){
            var msgCt = Ext.fly('msg-div');
            if(!msgCt){
                msgCt = Ext.DomHelper.insertFirst(document.body, {id:'msg-div'}, true);
            }
            msgCt.alignTo(document, 't-t');
            var s = String.format.apply(String, Array.prototype.slice.call(arguments, 1));
            var m = Ext.DomHelper.append(msgCt, {html:this.createBox(title, s)}, true);
            var delay = 10;
            if(title === this.szSuccess) {
              delay = 2;
            }
            m.slideIn('t').pause(delay).ghost("t", {remove:true,scope: this,callback:this.remove});
        }
        ,init : function(){ }
        ,remove : function() {var x = this; delete x;}
        ,createBox : function(t, s){
          return ['<div class="msg">',
                  '<div class="x-box-tl"><div class="x-box-tr"><div class="x-box-tc"></div></div></div>',
                  '<div class="x-box-ml"><div class="x-box-mr"><div class="x-box-mc"><h3>', t, '</h3>', s.replace(/\r\n/g, '<br />'), '</div></div></div>',
                  '<div class="x-box-bl"><div class="x-box-br"><div class="x-box-bc"></div></div></div>',
                  '</div>'].join('');
        }

};

/******************************************************************************/
Ext.xxv.Panel = function(config){
    Ext.apply(this, config);
    if(!this.id){
        this.id = Ext.id();
    }
};
Ext.xxv.Panel = Ext.extend(Ext.Panel, {
     title : "Connect ..."
    ,szLoading : "Loading ..."
    ,szTitle :  "Xtreme eXtension for VDR"
    ,LoadTitle : function(){
        this.setTitle(this.szLoading);
    }
    ,SetPanelTitle : function(str){
        this.setTitle(str);
        this.DocumentTitle(str);
    }
    ,DocumentTitle : function(str){
        document.title = str + " - " + this.szTitle;
    }

});

/******************************************************************************/
Ext.xxv.TagClouds = function(config){
    Ext.xxv.TagClouds.superclass.constructor.call(this, config);
    Ext.apply(this, config);
};

Ext.extend(Ext.xxv.TagClouds, Ext.Component, {

    initComponent : function(){
        Ext.xxv.TagClouds.superclass.initComponent.call(this);

	      this.addEvents({'selectKeyword' : true});
    },

    setvalue : function(keywords){

      this.keywords = keywords;

      if(this.cloudlist) {
        this.cloudlist.remove();
	      delete this.cloudlist;
	      this.cloudlist = null;
      }
   },

    render : function(ct, position){

      if(!this.cloudlist && this.keywords && this.keywords.length) {
        this.cloudlist = ct.createChild({tag: "ol", cls: "x-cloud-list"});
    		for(var i = 0, len = this.keywords.length; i < len; i++){
    			var child = this.cloudlist.createChild({
              tag: "li", 
              cls: "x-cloud-item "+this.getWeight(this.keywords[i][1]),
              html: '<a href="#">'+this.keywords[i][0]+'</a>'
              });
	
	        child.on('click', this.onSelectKeyWord, this);
        }
      }
    }
    /**************************************************************************/
	  ,getWeight : function(weight){
      var nmax = 100;
      var nmin = 0;

      var styles = new Array('smallest','smaller','small','medium','large','larger','largest');
      var value = weight / (nmax - nmin) * 6;
		  if(value >= 6.0)
			  return styles[6];
		  if(value <= 0.0)
			  return styles[0];

		  return styles[Math.round(value)];
	  }
    /**************************************************************************/
    ,onSelectKeyWord : function(e, t){
    
        var tag = t.firstChild.data;
        this.fireEvent('selectKeyword', tag);
        
        // Prevent the link href from being followed
        Ext.EventObject.stopEvent(e);
    }
});

Ext.reg('TagClouds', Ext.xxv.TagClouds);

