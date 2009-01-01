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
        ,remove : function() {delete this;}
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
Ext.xxv.checkboxes = Ext.extend(Ext.form.Field,  {
    /**
     * @cfg {String} focusClass The CSS class to use when the checkbox receives focus (defaults to undefined)
     */
    focusClass : undefined,
    /**
     * @cfg {String} fieldClass The default CSS class for the checkbox (defaults to "x-form-field")
     */
    fieldClass: "x-form-field",
    /**
     * @cfg {Boolean} checked True if the the checkbox should render already checked (defaults to false)
     */
    checked: false,
    /**
     * @cfg {String/Object} autoCreate A DomHelper element spec, or true for a default element spec (defaults to
     * {tag: "input", type: "checkbox", autocomplete: "off"})
     */
    defaultAutoCreate : { tag: "input", type: 'checkbox', autocomplete: "off"},
    /**
     * @cfg {String} boxLabel The text that appears beside the checkbox
     */
	
	getId:function(){
		//if multiple items are defined use this information
		if(this.items && this.items instanceof Array){
			if(this.items.length){
				var r=this.items[0];
				this.value=r.value;
				this.boxLabel=r.boxLabel;
				this.checked=r.checked || false;
				this.readOnly=r.readOnly || false;
				this.disabled=r.disabled || false;
				this.tabIndex=r.tabIndex;
				this.cls=r.cls;
				this.listeners=r.listeners;
				this.style=r.style;
				this.bodyStyle=r.bodyStyle;
				this.hideParent=r.hideParent;
				this.hidden=r.hidden;
			}
		}
		Ext.xxv.checkboxes.superclass.getId.call(this);
	},

	// private
    initComponent : function(){
        Ext.xxv.checkboxes.superclass.initComponent.call(this);
        this.addEvents(
            /**
             * @event change
             * Fires when the checkbox value changes.
             * @param {Ext.vx.checkboxes} this This checkbox
             * @param {Boolean} checked The new checked value
             */
            'check'
        );
    },

    // private
    onResize : function(){
        Ext.xxv.checkboxes.superclass.onResize.apply(this, arguments);
        if(!this.boxLabel){
            this.el.alignTo(this.wrap, 'c-c');
        }
    },
    
    // private
    initEvents : function(){
        Ext.xxv.checkboxes.superclass.initEvents.call(this);
        this.el.on("click", this.onClick,  this);
        this.el.on("change", this.onClick,  this);
    },

	// private
    getResizeEl : function(){
        return this.wrap;
    },

    // private
    getPositionEl : function(){
        return this.wrap;
    },

    /**
     * Overridden and disabled. The editor element does not support standard valid/invalid marking. @hide
     * @method
     */
    markInvalid : Ext.emptyFn,
    /**
     * Overridden and disabled. The editor element does not support standard valid/invalid marking. @hide
     * @method
     */
    clearInvalid : Ext.emptyFn,

    // private
    onRender : function(ct, position){
        Ext.xxv.checkboxes.superclass.onRender.call(this, ct, position);
        this.wrap = this.el.wrap({cls: "x-form-check-wrap"});
        if(this.boxLabel){
            this.wrap.createChild({tag: 'label', htmlFor: this.el.id, cls: 'x-form-cb-label', html: this.boxLabel});
        }
		if(!this.isInGroup){
			this.wrap.applyStyles({'padding-top':'2px'});
		}
        if(this.checked){
            this.setChecked(true);
        }else{
            this.checked = this.el.dom.checked;
        }
		if (this.items && this.items instanceof Array) {
			this.els=new Array();
			this.els[0]=this.el;
			for(var i=1;i<this.items.length;i++){
				var r=this.items[i];
				this.els[i]=new Ext.xxv.checkboxes({
					renderTo:this.wrap,
					hideLabel:true,
					boxLabel:r.boxLabel,
					checked:r.checked || false,
					value:r.value,
					name:this.name || this.id,
					readOnly:r.readOnly || false,
					disabled:r.disabled || false,
					tabIndex:r.tabIndex,
					cls:r.cls,
					listeners:r.listeners,
					style:r.style,
					bodyStyle:r.bodyStyle,
					hideParent:r.hideParent,
					hidden:r.hidden,
					isInGroup:false
				});
				if (this.horizontal) {
					this.els[i].el.up('div.x-form-check-wrap').applyStyles({
						'display': 'inline',
						'padding-left': '5px'
					});
				}
			}
			if(this.hidden)this.hide();
		}
    },
    
    initValue : function(){
        if(this.value !== undefined){
            this.el.dom.value=this.value;
        }else if(this.el.dom.value.length > 0){
            this.value=this.el.dom.value;
        }
    },
	
    // private
    onDestroy : function(){
		if (this.items && this.items instanceof Array) {
			var cnt = this.items.length;
			for(var x=1;x<cnt;x++){
				this.els[x].destroy();
			}
		}
        if(this.wrap){
            this.wrap.remove();
        }
        Ext.xxv.checkboxes.superclass.onDestroy.call(this);
    },

	setChecked:function(v){
        if(this.el && this.el.dom){
			var fire = false;
			if(v != this.checked)fire=true;
			this.checked=v;
            this.el.dom.checked = this.checked;
            this.el.dom.defaultChecked = this.checked;
    	    if(fire)this.fireEvent("check", this, this.checked);
	    }
    },
    /**
     * Returns the value of the checked checkbox.
     * @return {Mixed} value
     */
    getValue : function(){
        if(!this.rendered) {
            return this.value;
        }
        var p=this.el.up('form');//restrict to the form if it is in a form
    		if(!p)p=Ext.getBody();
//    var c=p.child('input[name='+this.el.dom.name+']:checked', true);
//  return (c)?c.value:this.value;
//		return (c)?c.value:null;
      var result = [];
			var els = p.select('input[name=' + this.el.dom.name + ']');
			els.each(function(el){
					var e = Ext.getCmp(el.dom.id);
          if(e.checked)
            result.push(e.value);
			}, this);
      if(result.length)
        return result.join(',');
      return null;
    },

	// private
    onClick : function(){
        if(this.el.dom.checked != this.checked){
  					this.setChecked(this.checked ? false : true);
        }
    },

    /**
     * Checks the checkbox box with the matching value
     * @param {Mixed} v
     */

    setValue : function(v){
        if(!this.rendered) {
            this.value=v;
            return;
        }
        var p=this.el.up('form');//restrict to the form if it is in a form
        if(!p)p=Ext.getBody();
        var target = p.child('input[name=' + this.el.dom.name + '][value=' + v + ']', true);
        if (target) target.checked = true;
    }	
});
Ext.reg('xxv-checkboxes', Ext.xxv.checkboxes);

/******************************************************************************/

Ext.xxv.slide = function(config){
    Ext.xxv.slide.superclass.constructor.call(this, config);
    
    Ext.apply(this, config);
        
};

Ext.extend(Ext.xxv.slide, Ext.Component, {

	baseCls : 'x-slide',

    setSize : Ext.emptyFn,
    setWidth : Ext.emptyFn,
    setHeight : Ext.emptyFn,
    setPosition : Ext.emptyFn,
    setPagePosition : Ext.emptyFn,

    initComponent : function(){
        Ext.xxv.slide.superclass.initComponent.call(this);

	    this.addEvents({'selected' : true});
        if (typeof(this.imageGap)=='undefined') { this.imageGap = 10 }
        this.tpl = new Ext.Template(
            '<div class="preview-header">',
            '<h3 class="preview-title">{title}</h3><div class="preview-channel">{period}</div>',
            '<h4 class="preview-shorttitle">{subtitle}&nbsp;</h4>',
            '<div class="preview-date">{day:date} {start} - {stop}</div>',
            '</div>',
            '<div class="{cls}-wrap">',
                '<div id="images-inner" class="{cls}-inner">',
	                '<div class="{cls}-images-wrap">',
	                    '<div class="{cls}-images"></div>',
	                '</div>',
	            '</div>',
            '</div>',
            '<div class="preview-body">{content}</div>'
        );
        this.tpl.compile();  

        this.tplimg = new Ext.Template('{day:date} - {start} ({period})');
        this.tplimg.compile();  

    },

    setvalue : function(data){

                      var Woerter = data.fulltitle.split("~");
                      this.title = '';
                      if(Woerter.length >1) {
                        var i = 0;
                        for(len = Woerter.length - 1; i < len; i++){
                          if(this.title.length) {
                            this.title += '~';
                          }
                          this.title += Woerter[i];
                        }
                        this.subtitle = Woerter[i];
                      } else {
                        this.title = data.fulltitle;
                        this.subtitle = '';
                      }

                      this.content = data.description.replace(/\r\n/g, '<br />');

                      this.day     = data.day;
                      this.start   = data.day.dateFormat('H:i');
                      this.stop    = new Date(data.day.getTime() + (data.duration * 1000)).dateFormat('H:i');
                      this.tperiod = new Date(new Date().clearTime().getTime()+(data.duration * 1000));
                      this.period  = this.tperiod.dateFormat('H:i:s');

                      this.images = [];
                      var frames = data.preview.split(",");
                      Ext.each(frames, function(frame){ 
                        var url = "?cmd=ri&data="+data.id+"_"+frame;
                        var day = new Date(data.day.getTime() + (frame * 40));
                        var tperiod = new Date(new Date().clearTime().getTime()+(frame * 40));
                        this.images.push(
                          {
                               src:     url
                              ,day:     day
                              ,start:   day.dateFormat('H:i')
                              ,tperiod: tperiod
                              ,period:  tperiod.dateFormat('H:i:s')
                          }
                        );
                      },this);
                    },

    render : function(ct, position){




        var inner= Ext.get("images-inner");
        if(!inner) {
          var param = {
            title: this.title,
            subtitle: this.subtitle,
            day: this.day,
            start: this.start,
            stop: this.stop,
            period: this.period,
            content: this.content,
            cls: this.baseCls
          };
          if(position){
              this.el = this.tpl.insertBefore(position, param, true);
          }else{
              this.el = this.tpl.append(ct, param, true);
          }
          if(this.id){
              this.el.dom.id = this.id;
          }
          
          inner= Ext.get("images-inner");
        }
        var imagesWrap = Ext.get(inner.dom.firstChild);
        this.divImages = Ext.get(imagesWrap.dom.firstChild);

        var size = inner.getSize();
        this.width = size.width;
        this.height = size.height;

		inner.setStyle({
			height:(this.imageHeight + (2*this.wrapMarginY)) + 'px',
			width:this.width+'px'
		});
		
		var totalImageWidth=this.imageWidth+this.imageGap;
		var usableWidth=this.width-(this.wrapMarginX*2);
		var maxPicsOnce=Math.floor(usableWidth/totalImageWidth);
		var usedWidth=maxPicsOnce*totalImageWidth-this.imageGap;
		var offsetLeft=Math.floor((usableWidth-usedWidth)/2);
		this.pageSize=usedWidth+this.imageGap;
		this.maxPages=Math.round(this.images.length/maxPicsOnce+.04999);
		this.curPage=0;

		if (!Ext.isIE){
			offsetLeft+=this.wrapMarginX;
		}
		
		imagesWrap.setStyle({
			position: 'absolute',
			clip:'rect(0,'+(usedWidth*1)+','+(this.imageHeight)+',0)',
			'margin-top':this.wrapMarginY+'px',
			width:this.width+'px',
			height:this.imageHeight+'px',
			'margin-left':offsetLeft+'px'
		});

		/*this.divImages.setStyle({
			position: 'absolute'
		});*/

    Ext.each(this.images, function(image){            

      if (typeof(image)=='string'){
        image={src:image}
      }
      var qtip = this.tplimg.applyTemplate(image);

      thisImage = this.divImages.createChild({tag:"img", src:image.src, 
      'ext:qtip':qtip,
       style:{
       'margin-right': this.imageGap+'px',
        width:  this.imageWidth+'px'
//      height: this.imageHeight+'px'            	
       }
      });

      thisImage.on("click", function(e, ele){
        if (!image.onSelected || !(image.onSelected.call(this, image, e, ele )===false)){
          this.fireEvent('selected', this, image, e, ele);                
        }
      },this);
    },this);

    },

    CanShift: function(direction) {
  		if (!this.curPage){
  			this.offsetLeft=this.divImages.getLeft();
  		}
  		var newPage=(direction=='right' ? this.curPage+1 : this.curPage-1 );
      if (newPage<0 || newPage >= this.maxPages){
		  	return -1;
		  }
      return newPage;
    },

    Shift: function(direction) {
      var newPage = this.CanShift(direction);
      if (newPage<0 || newPage >= this.maxPages){
		  	return;
		  }
		  this.curPage=newPage;
		  var newLocation=(this.pageSize*this.curPage)*-1+this.offsetLeft;
		  this.divImages.shift({ x:newLocation, duration: this.duration || .7 });
    }
});

Ext.reg('slide', Ext.xxv.slide);

