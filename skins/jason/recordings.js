/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */
/******************************************************************************/
SecondsToHMS = function(t) {
  return new Date(new Date().clearTime().getTime()+(t * 1000)).dateFormat('H:i:s')
}

/******************************************************************************/
HMSToSeconds = function(s) {
  var seconds;
  var tt = s.replace(/\..*/g, '');
  var x = tt.split(":");
  seconds = parseInt(x.pop());
  if(x.length > 0) {
    seconds += ( 60 * parseInt(x.pop()));
  }
  if(x.length > 0) {
    seconds += (3600 * parseInt(x.pop()));
  }
  return seconds;
}

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
    slider: null,

    initComponent : function(){
        Ext.xxv.slide.superclass.initComponent.call(this);

	    this.addEvents({'selected' : true});
        if (typeof(this.imageGap)=='undefined') { this.imageGap = 10 }
        this.tpl = new Ext.Template(
            '<div class="preview-header">',
            '<h3 class="preview-title">{title}</h3>',
            '<div class="preview-channel">{channel}{period}{cutlength}</div>',
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
            '<div id="slider"><div id="slider-inner"></div></div>',
            '<div class="preview-body">{content}</div>',
            '<div class="preview-body">{keywords}</div>'
        );
        this.tpl.compile();  

        this.tplimg = new Ext.Template('{day:date} - {start} ({period})');
        this.tplimg.compile();  

    },

    setvalue : function(data, first){

      this.param = {
         title:     data.fulltitle
        ,subtitle:  ''
        ,channel:   (!data.channel || data.channel.length <= 0) ? null : ( '<b>' + data.channel + '</b> - ' )
        ,day:       data.day
        ,duration:  data.duration
        ,start:     data.day.dateFormat('H:i')
        ,stop:      new Date(data.day.getTime() + (data.duration * 1000)).dateFormat('H:i')
        ,content:   data.description.replace(/\r\n/g, '<br />')
        ,cutlength: data.cutlength == data.duration ? null : (' (' + SecondsToHMS(data.cutlength) +')')
        ,period:    SecondsToHMS(data.duration)
        ,marks:     data.marks
      };
      if(data.keywords) {
        var k = new Array();
        for(var j = 0, len = data.keywords.length; j < len; j++){
          k.push(data.keywords[j][0]);
        }
        this.param.keywords = k.join(', ');
      }

      var title = data.fulltitle.split("~");
      if(title.length >1) {
        this.param.subtitle = title.pop();
        this.param.title = title.join("~");
      }

      if(first === true) {
        var images = [];
        if(!data.preview || data.preview == '') {
          /*var day = new Date(data.day.getTime());
          images.push(
            {
                 src:     (data.type == 'RADIO') ? 'pic/radio.png' : 'pic/movie.png'
                ,day:     day
                ,start:   day.dateFormat('H:i')
                ,frame:   0
                ,period:  SecondsToHMS(0)
            }
          );*/
        } else {
          var frames = data.preview.split(",");
          Ext.each(frames, function(frame){ 
            var url = "?cmd=ri&data="+data.id+"_"+frame;
            var day = new Date(data.day.getTime() + (frame * 40));
            images.push(
              {
                   src:     url
                  ,day:     day
                  ,start:   day.dateFormat('H:i')
                  ,frame:   frame
                  ,period:  SecondsToHMS((frame * 40)/1000)
              }
            );
          },this);
        }
       this.images = images;
      }
    },

    render : function(ct, position){

        var inner= Ext.get("images-inner");
        if(!inner) {
          this.param.cls = this.baseCls;
          if(position){
              this.el = this.tpl.insertBefore(position, this.param, true);
          }else{
              this.el = this.tpl.append(ct, this.param, true);
          }
          if(this.id){
              this.el.dom.id = this.id;
          }
          
          inner= Ext.get("images-inner");
		  if(this.slider) {
			delete this.slider;
			this.slider = null;
		  }
        }
        var imagesWrap = Ext.get(inner.dom.firstChild);
        this.divImages = Ext.get(imagesWrap.dom.firstChild);

        var size = inner.getSize();
        this.width = size.width;
        this.height = size.height;

    		inner.setStyle({
		    	height:(this.imageHeight + (2*this.wrapMarginY)) + 'px',
		    	width:(this.width-this.wrapMarginX)+'px'
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
              this.fireEvent('selected', this, new Date(new Date().clearTime().getTime()+(image.frame * 40)), e, ele);

              var slider = this.slider.getSlider('cutpoint_thumb');
              slider.value = image.frame/25;
              this.slider.initSliderPosition(slider);
            }
          },this);
        },this);

        if(this.slider) {
          this.slider.sliders.clear();
        } else {

		    this.slider = new Ext.ux.SlideZone('slider-inner', {  
			    type: 'horizontal',
			    size: usableWidth-32,
          sliderWidth: 16,
			    sliderHeight: 24,
			    maxValue: this.param.duration,
			    minValue: 0,
			    //sliderSnap: 1,
			    allowSliderCrossing: true
			});
			this.ts = new Ext.ux.ThumbSlider({
				 value: 0
				,name: 'cutpoint_thumb'
				,cls: 'x-slide-zone-bottom'
				,allowMove: true
			});
			this.ts.on('drag',
				function() {
					var v = parseInt(this.ts.value * 1000);
					this.fireEvent('selected', this, new Date((new Date().clearTime().getTime())+v), null, null);
			},this);
		}

        if(this.param.marks && this.param.marks.length) {
			var cutpoint = this.param.marks.split(",");
			for(var i = 0, len = cutpoint.length; i < len; i += 2){
				var first = HMSToSeconds(cutpoint[i]);
				var second;
				if(i+1 < cutpoint.length) {
					second = HMSToSeconds(cutpoint[i+1]);
				} else {
					second = this.param.duration;
				}
				var rs = new Ext.ux.RangeSlider({
					 value: [first,second]
					,name: 'cutpoint_'+i
					,cls: 'x-slide-zone-top'
					,allowMove: false
				});
				this.slider.add(rs);	
			}
		}
		this.slider.add(this.ts);
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

/******************************************************************************/

Ext.DataView.LabelEditor = function(cfg, field){
    Ext.DataView.LabelEditor.superclass.constructor.call(this,
        field || new Ext.form.TextField({
            allowBlank: false,
            growMin:90,
            growMax:240,
            grow:true,
            selectOnFocus:true
        }), cfg
    );
}

Ext.extend(Ext.DataView.LabelEditor, Ext.Editor, {
    alignment: "tl-tl",
    hideEl : false,
    cls: "x-small-editor",
    shim: false,
    completeOnEnter: true,
    cancelOnEsc: true,
    labelSelector: 'span.x-editable',

    init : function(view){
        this.view = view;
        view.on('render', this.initEditor, this);
        this.on('complete', this.onSave, this);
    },

    initEditor : function(){
        this.view.getEl().on('mousedown', this.onMouseDown, this, {delegate: this.labelSelector});
    },

    onMouseDown : function(e, target){
        if(!e.ctrlKey && !e.shiftKey){
            var item = this.view.findItemFromChild(target);
            e.stopEvent();
            var record = this.view.store.getAt(this.view.indexOf(item));
            if(record.data[this.allow]) {
              this.startEdit(target, record.data[this.dataIndex]);
              this.activeRecord = record;
            }
        }else{
            e.preventDefault();
        }
    },

    onSave : function(ed, value){
        this.activeRecord.set(this.dataIndex, value);
    }
});

/******************************************************************************/

Ext.DataView.DragSelector = function(cfg){
    cfg = cfg || {};
    var view, regions, proxy, tracker;
    var rs, bodyRegion, dragRegion = new Ext.lib.Region(0,0,0,0);
    var dragSafe = cfg.dragSafe === true;

    this.init = function(dataView){
        view = dataView;
        view.on('render', onRender);
    };

    function fillRegions(){
        rs = [];
        view.all.each(function(el){
            rs[rs.length] = el.getRegion();
        });
        bodyRegion = view.el.getRegion();
    }

    function cancelClick(){
        return false;
    }

    function onBeforeStart(e){
        return !dragSafe || e.target == view.el.dom;
    }

    function onStart(e){
        view.on('containerclick', cancelClick, view, {single:true});
        if(!proxy){
            proxy = view.el.createChild({cls:'x-view-selector'});
        }else{
            proxy.setDisplayed('block');
        }
        fillRegions();
        view.clearSelections();
    }

    function onDrag(e){
        var startXY = tracker.startXY;
        var xy = tracker.getXY();

        var x = Math.min(startXY[0], xy[0]);
        var y = Math.min(startXY[1], xy[1]);
        var w = Math.abs(startXY[0] - xy[0]);
        var h = Math.abs(startXY[1] - xy[1]);

        dragRegion.left = x;
        dragRegion.top = y;
        dragRegion.right = x+w;
        dragRegion.bottom = y+h;

        dragRegion.constrainTo(bodyRegion);
        proxy.setRegion(dragRegion);

        for(var i = 0, len = rs.length; i < len; i++){
            var r = rs[i], sel = dragRegion.intersect(r);
            if(sel && !r.selected){
                r.selected = true;
                view.select(i, true);
            }else if(!sel && r.selected){
                r.selected = false;
                view.deselect(i);
            }
        }
    }

    function onEnd(e){
        if(proxy){
            proxy.setDisplayed(false);
        }
    }

    function onRender(view){
        tracker = new Ext.dd.DragTracker({
            onBeforeStart: onBeforeStart,
            onStart: onStart,
            onDrag: onDrag,
            onEnd: onEnd
        });
        tracker.initEl(view.el);
    }
};

/******************************************************************************/

Ext.xxv.recordingsStore = function() {

    // create the data store
    return new Ext.data.Store({
             baseParams:{cmd:'rl'}
            ,autoLoad:{params:{start:0, limit:configuration.pageSize}}
            ,reader: new Ext.xxv.jsonReader({
                    fields: [
                       {name: 'id', type: 'string'}
                      ,{name: 'eventid', type: 'int'}
                      ,{name: 'title', type: 'string'}
                      ,{name: 'subtitle', type: 'string'}
                      ,{name: 'duration', type: 'int'}
                      ,{name: 'day', type:'date', dateFormat:'timestamp'}
                      ,{name: 'unviewed', type: 'int'}
                      ,{name: 'type', type: 'string'}
                      ,{name: 'group', type: 'int'}
                      ,{name: 'fulltitle', type: 'string'}
                      ,{name: 'isrecording', type: 'int'}
                      ,{name: 'description', type: 'string'}
                      ,{name: 'preview', type: 'string'}
                      ,{name: 'cutlength', type: 'int'}
                      //*** filled later by rdisplay ***
                      ,{name: 'channel', type: 'string'}
                      ,{name: 'marks', type: 'string'}
                      ,{name: 'lifetime', type: 'int'}
                      ,{name: 'priority', type: 'int'}
                      ,{name: 'keywords', type: 'string'}
                    ]
                })
            ,proxy : new Ext.data.HttpProxy({
                 url: XXV.help.baseURL()
                ,method: 'POST'
            })
    });
};

Ext.xxv.recordingsDataView = function(viewer, preview, store, config) {
    this.viewer = viewer;
    this.preview = preview;
    Ext.apply(this, config);
    // create the data store
    this.store = store;
    var tpl = new Ext.XTemplate(
    '<tpl for=".">',
        '<div class="thumb-wrap" id="{id}">',
		    '<div class="thumb">',
        '<tpl if="isrecording == 0">',
            '<img src="pic/folder.png"<tpl if="group != 0"> ext:qtitle="{shortTitle}" ext:qtip="{group} recordings ({period})"</tpl>/>',
        '</tpl>',
        '<tpl if="isrecording != 0">',
        '<tpl if="this.isRadio(type)">',
            '<img src="pic/radio.png" ext:qtitle="{shortTitle}" ext:qtip="{day:date} - {start} - {stop} ({period})<br />{shortDesc}" />',
        '</tpl>',
        '<tpl if="this.isRadio(type) == false">',
            '<tpl if="frame == -1">',
                '<img src="pic/movie.png" ext:qtitle="{shortTitle}" ext:qtip="{day:date} - {start} - {stop} ({period})<br />{shortDesc}" />',
            '</tpl>',
            '<tpl if="frame != -1">',
                '<img src="?cmd=ri&data={id}_{frame}" ext:qtitle="{shortTitle}" ext:qtip="{day:date} - {start} - {stop} ({period})<br />{shortDesc}" />',
            '</tpl>',
        '</tpl>',
        '</tpl>',
            '<tpl if="unviewed != 0">',
                '<div class="unviewed"></div>',
            '</tpl>',
        '</div>',
		    '<span class="x-editable">{shortName}</span></div>',
        '</tpl>',
        '<div class="x-clear"></div>', {
         isRadio: function(name){
             return name == 'RADIO';
         }
      }
  	);

    this.filter = new Ext.ux.grid.Search({
         position:'owner'
        ,shortcutKey:null
        ,paramNames: {
              fields:'cmd'
              ,all:'rl'
              ,cmd:'rs'
              ,query:'data'
        }
    });
    Ext.xxv.recordingsDataView.superclass.constructor.call(this, {
                    region: 'center'
                    ,store: store
                    ,tpl: tpl
                    ,cls: 'x-panel-body' // workaround - add missing border
                    ,style: 'overflow:auto'
                    ,multiSelect: true
                    ,overClass:'x-view-over'
                    ,itemSelector:'div.thumb-wrap'
                    ,loadMask:true
                    ,prepareData: function(data){
                      if(data.id != 'up' && this.store.lastOptions.params.data && this.store.lastOptions.params.cmd == 'rl') {

                        var Woerter = data.fulltitle.split("~");
                        var last = this.store.lastOptions.params.data.split("~");
                        var i = (Woerter.length > last.length) ? last.length : (Woerter.length - 1);
                        var title = '';
                        for(len = Woerter.length; i < len; i++){
                          if(title.length) { title += '~'; }
                          title += Woerter[i];
                        }
                        data.shortName = Ext.util.Format.ellipsis(title, 16);
                      } else {
                        data.shortName = Ext.util.Format.ellipsis(data.fulltitle, 16);
                      }
                      data.shortTitle = Ext.util.Format.ellipsis(data.fulltitle, 50).replace(/\"/g,'\'');
                      data.shortDesc = Ext.util.Format.ellipsis(data.description, 50).replace(/\"/g,'\'');
                      data.start = data.day.dateFormat('H:i');
                      data.stop =  new Date(data.day.getTime() + (data.duration * 1000)).dateFormat('H:i');
                      data.period =  SecondsToHMS(data.duration);
                      var frames = data.preview.split(",");
                      if(data.preview.length && frames.length) {
                        var item = (frames.length) / 2;
                        data.frame = frames[item.toFixed(0)];
                      } else {
                        data.frame = -1;
                      }
                      return data;
                    }
                    ,listeners: {
			             'selectionchange': {fn:this.doClick, scope:this, buffer:100}
 		                    ,'contextmenu'    : {fn:this.onContextClick, scope:this}
  			                ,'dblclick'       : {fn:this.doDblclick, scope:this}
//			                ,'loadexception'  : {fn:this.onLoadException, scope:this}
   			                ,'beforeselect'   : {fn:function(view){ return view.store.getRange().length > 0; } }
		                }
                   ,plugins: [
                      new Ext.DataView.DragSelector()                   //,new Ext.DataView.LabelEditor({dataIndex: 'fulltitle', allow: 'isrecording'})
                     ,this.filter
                   ]
                  }
  );

  this.store.on({
     'beforeload' : this.onBeforeLoad
    ,'load' : this.onLoad
    ,'loadexception' : this.onLoadException
    ,scope:this
  });
};

Ext.extend(Ext.xxv.recordingsDataView,  Ext.DataView, {

     szTitle         : "Recordings"
    ,szToolTip       : "Display recordings"
    ,szFindReRun     : "Find rerun"
    ,szEdit          : "Edit"
    ,szCut           : "Cut"
    ,szDelete        : "Delete"
    ,szRecover       : "Recover deleted recordings"
    ,szStream        : "Stream recording"
    ,szPlay          : "Playback"
    ,szLoadException : "Couldn't get data about recording!\r\n{0}"
    ,szCutSuccess    : "Recordings started cutting process successful.\r\n{0}"
    ,szCutFailure    : "Couldn't start cutting process recordings!\r\n{0}"
    ,szDeleteSuccess : "Recordings deleted successful.\r\n{0}"
    ,szDeleteFailure : "Couldn't delete recordings!\r\n{0}"
    ,szPlayBackSuccess : "Recording started playback successful.\r\n{0}"
    ,szPlayBackFailure : "Couldn't started playback recording!\r\n{0}"
    ,szUpgrade        : "Update list of recordings"
    ,szUpgradeWait    : "Please wait..."
    ,szUpgradeSuccess : "List of recordings update successful.\r\n{0}"
    ,szUpgradeFailure : "Couldn't update list of recordings!\r\n{0}"
	,szDetailsFailure : "Couldn't update details of recording!\r\n{0}"

    ,onLoadException :  function( scope, o, arg, e) {
	    new Ext.xxv.MessageBox().msgFailure(this.szLoadException, e);
    }
    ,onBeforeLoad :  function( scope, params ) {
      if(this.DetailsTransaction) 
        Ext.Ajax.abort(this.DetailsTransaction);
	    this.preview.clear();
    }
    ,onLoad :  function( store, records, opt ) {

      // Add folder to go to back folder
      if(store.lastOptions && store.lastOptions.params && store.lastOptions.params.data) {
        var Recording = Ext.data.Record.create( store.fields.items );
        store.insert(0,[new Recording(
              {id: 'up',
               eventid: 0,
               title: '..',
               subtitle: '',
               duration: 0,
               day: new Date(), 
               unviewed: 0,
               type: '',
               group: 0,
               fulltitle: '..',
               isrecording: 0,
               description: '',
               preview: ''},'up')]);
      }

      // Show details from first recording
      for(var i = 0, len = store.getCount(); i < len; i++){
        var record = store.getAt(i);
          if(record.data.isrecording != 0) {
            this.showDetails(record);
            //this.select(record.data.id,false,false);
            break;
          }
       }
       if(store.reader.meta.param) {
        var tb = this.ownerCt.getTopToolbar();
        tb.displayMsg = store.reader.meta.param.usage;
        tb.displayMsg += ' - ';
        tb.displayMsg += Ext.PagingToolbar.prototype.displayMsg;
       }
       if(store.title) {
    	  this.ownerCt.SetPanelTitle(store.title);
       } else {
    	  this.ownerCt.SetPanelTitle(this.szTitle);
       }

    }
    ,doDblclick : function() {
	      var selNode = this.getSelectedNodes();
  		  if(selNode && selNode.length > 0){
          var firstNode = selNode[0];
          var record = this.store.getById(firstNode.id);
          if(record) {
            if(record.data.isrecording == 0) {
                delete(this.store.baseParams['data']);
                this.store.title = undefined;

                this.store.baseParams.cmd = 'rl';
                if(record.id == 'up') {
                  var f = this.filter.field.getValue();
                  if(f && f != '') {
                    this.filter.field.setValue('');
                  }
                  var Woerter = this.store.lastOptions.params.data.split("~");
                  Woerter.pop();
                  var title = Woerter.join('~');
                  if(title != '') {
                    this.store.title = title;
                    this.store.baseParams.data = title;
                  }
                } else {
                  this.store.title = record.data.fulltitle;
                  this.store.baseParams.data = record.data.fulltitle;
                }
                this.store.load({params:{start:0, limit:this.store.autoLoad.params.limit}});
              } else {
                this.EditItem(record);
              }
            }
        }
    },

	  doClick : function(){
	      var selNode = this.getSelectedNodes();
  		  if(selNode && selNode.length > 0){
          var record = this.store.getById(selNode[0].id);
          this.showDetails(record);
        }
    },
	  showDetails : function(record){
        this.preview.content(record);
        this.DetailsItem(record);
	  }, 
/******************************************************************************/
    onDetailsSuccess : function( response,options ) 
    { 
        var o = eval("("+response.responseText+")");

        if(o && o.data && typeof(o.data) == 'object' 
             && o.param) {

            var RecordingsID = options.params.data.split(",");
            for(var j = 0, len = RecordingsID.length; j < len; j++){
              var iSel = this.store.indexOfId(RecordingsID[j]);
              if(iSel === -1 
                || this.store.data.items[iSel].id != o.data.RecordId)
                continue;

              this.store.data.items[iSel].data.channel  = o.data.Channel;
              this.store.data.items[iSel].data.marks    = o.data.Marks;
              this.store.data.items[iSel].data.lifetime = parseInt(o.data.lifetime);
              this.store.data.items[iSel].data.priority = parseInt(o.data.priority);
              this.store.data.items[iSel].data.keywords = o.data.keywords;

              var record = this.store.getById(RecordingsID[j]);
              this.preview.update(record);
            }

        } else {
            var msg = '';
            if(o && o.data && typeof(o.data) == 'string') {
              msg = o.data;
            }
            new Ext.xxv.MessageBox().msgFailure(this.szDetailsFailure, msg);
        }
    },

    onDetailsFailure : function( response,options ) 
    { 
        new Ext.xxv.MessageBox().msgFailure(this.szDetailsFailure, response.statusText);
    },

    DetailsItem : function(record) {
      if(record.data.priority 
      || record.data.id == 'up') {
        return;
      }
      var toDetails = '';
      if(record && record.data) {
        toDetails = record.data.id;
      } else {
	      var selNode = this.getSelectedNodes();
		    if(selNode && selNode.length > 0){
          for(var i = 0, len = selNode.length; i < len; i++){
            if(selNode[i].id == 'up')
              continue;
            if(toDetails.length) {
              toDetails += ',';
            }
            var record = this.store.getById(selNode[i].id);
            if(record.data.isrecording == 0) {
              //toDetails += 'all:';
              continue;
            }
            toDetails += record.data.id;
          }
        }
      }
      if(toDetails.length) {
      if(this.DetailsTransaction) 
        Ext.Ajax.abort(this.DetailsTransaction);
      this.DetailsTransaction = Ext.Ajax.request({
            scope: this
           ,url: XXV.help.cmdAJAX('rd')
           ,timeout: 15000
           ,success: this.onDetailsSuccess
           ,failure: this.onDetailsFailure
           ,params:{ data: toDetails }
        });
      }
    },  
/******************************************************************************/
    onContextClick : function(grid, index, node, e){
        if(!this.menu){ // create context menu on first right click
            this.menu = new Ext.menu.Menu({
                id:'grid-ctx',
                items: [
                   {
                     id: 's'
                    ,text: this.szFindReRun
                    ,iconCls: 'find-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function(){ this.viewer.searchTab(this.ctxRecord);}
                   },{
                     id: 're'
                    ,text: this.szEdit
                    ,iconCls: 'edit-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function() { this.EditItem(this.ctxRecord); }
                   },{
                     id: 'rcu'
                    ,text: this.szCut
                    ,iconCls: 'cut-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function() { this.CutItem(null); }
                   },{
                     id: 'rr'
                    ,text: this.szDelete
                    ,iconCls: 'delete-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function() { this.DeleteItem(null); }
                   },'-',{
                     id: 'pre'
                    ,text: this.szStream
                    ,iconCls: 'stream-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function(){ this.onStream(this.ctxRecord,'00:00:00');}
                   },{
                     id: 'rpv'
                    ,text: this.szPlay
                    ,iconCls: 'play-icon'
                    ,scope:this
                    ,disabled: true
                    ,handler: function(){ this.onPlay(this.ctxRecord,'00:00:00');}
                   }
                ]
            });
            this.menu.on('hide', this.onContextHide, this);
        }
        e.stopEvent();
        if(this.ctxRow){
            //Ext.fly(this.ctxRow).removeClass('x-view-selected');
            this.ctxRow = null;
        }
        this.ctxRow = node;
        var record = this.store.getById(node.id);
        this.select(node.id,true,false);

        var items = this.menu.items;
        if(items) { 
          items.eachKey(
            function(key, f) {
              var enable = XXV.help.cmdAllowed(key);
              if(enable) {
                switch(key) {
                  case 's':   enable = (record.data.isrecording == 0) ? false : true; break;
                  case 're':  enable = (record.data.isrecording == 0) ? false : true; break;
                  case 'rpv': enable = (record.data.isrecording == 0) ? false : true; break;
                  case 'pre': enable = (record.data.isrecording == 0) ? false : true; break;
                }
                if(enable && node.id != 'up') {
                  f.enable();
                }
              }
            },items); 
        }
        this.ctxRecord = record;

        //Ext.fly(this.ctxRow).addClass('x-view-selected');
        this.menu.showAt(e.getXY());
    },

    onContextHide : function(){
        if(this.ctxRow){
            Ext.fly(this.ctxRow).removeClass('x-view-selected');
            this.ctxRow = null;
        }
    },

/******************************************************************************/
    onCutSuccess : function( response,options ) 
    { 
        this.el.unmask();
        var o = eval("("+response.responseText+")");

        if(o && o.data && typeof(o.data) == 'string' 
             && o.param && o.param.state && o.param.state == 'success') {

            new Ext.xxv.MessageBox().msgSuccess(this.szCutSuccess, o.data);

        } else {
            var msg = '';
            if(o && o.data && typeof(o.data) == 'string') {
              msg = o.data;
            }
            new Ext.xxv.MessageBox().msgFailure(this.szCutFailure, msg);
        }
    },

    onCutFailure : function( response,options ) 
    { 
        this.el.unmask();

        new Ext.xxv.MessageBox().msgFailure(this.szCutFailure, response.statusText);
    },

    CutItem : function(record) {

      var toCut = '';
      if(record && record.data) {
        toCut = record.data.id;
      } else {
	      var selNode = this.getSelectedNodes();
		    if(selNode && selNode.length > 0){
          for(var i = 0, len = selNode.length; i < len; i++){
            if(selNode[i].id == 'up')
              continue;
            if(toCut.length) {
              toCut += ',';
            }
            var record = this.store.getById(selNode[i].id);
            if(record.data.isrecording == 0) {
              //toCut += 'all:';
              continue;
            }
            toCut += record.data.id;
          }
        }
      }
      if(toCut.length) {
        this.el.mask(Ext.LoadMask.prototype.msg, 'x-mask-loading');
        Ext.Ajax.request({
            scope: this
           ,url: XXV.help.cmdAJAX('rcu')
           ,timeout: 15000
           ,success: this.onCutSuccess
           ,failure: this.onCutFailure
           ,params:{ data: toCut }
        });
      }
    },  
/******************************************************************************/
    onDeleteSuccess : function( response,options ) 
    { 
        this.el.unmask();
        var o = eval("("+response.responseText+")");

        if(o && o.data && typeof(o.data) == 'string' 
             && o.param && o.param.state && o.param.state == 'success') {

            new Ext.xxv.MessageBox().msgSuccess(this.szDeleteSuccess, o.data);

            var RecordingsID = options.params.data.split(",");
            var selRecord;
            var iSel = 0;

            for(var j = 0, len = RecordingsID.length; j < len; j++){
              var record = this.store.getById(RecordingsID[j].replace(/all:/g, ''));
              if(!record)
                continue;
              iSel = this.store.indexOf(record) - 1;
              this.store.remove(record);
            }
            if(iSel >= 0 && iSel < this.store.getCount()) {
              selRecord = this.store.getAt(iSel);
            }
            if(!selRecord || selRecord.data.isrecording == 0) {
              for(iSel++;iSel < store.getCount();iSel++) {
                selRecord = this.store.getAt(iSel);
                if(selRecord.data.isrecording != 0)
                  break;
              }
            }
            if(selRecord && selRecord.data.isrecording != 0) {
                this.select(selRecord.data.id,false,false);
            }

        } else {
            var msg = '';
            if(o && o.data && typeof(o.data) == 'string') {
              msg = o.data;
            }
            new Ext.xxv.MessageBox().msgFailure(this.szDeleteFailure, msg);
        }
    },

    onDeleteFailure : function( response,options ) 
    { 
        this.el.unmask();

        new Ext.xxv.MessageBox().msgFailure(this.szDeleteFailure, response.statusText);
    },

    DeleteItem : function(record) {

      var todelete = '';
      if(record && record.data) {
        todelete = record.data.id;
      } else {
	      var selNode = this.getSelectedNodes();
		    if(selNode && selNode.length > 0){
          for(var i = 0, len = selNode.length; i < len; i++){
            if(selNode[i].id == 'up')
              continue;
            if(todelete.length) {
              todelete += ',';
            }
            var record = this.store.getById(selNode[i].id);
            if(record.data.isrecording == 0) {
              todelete += 'all:';
            }
            todelete += record.data.id;
          }
        } 
      }
      if(todelete.length) {
        this.el.mask(Ext.LoadMask.prototype.msg, 'x-mask-loading');
        Ext.Ajax.request({
            scope: this
           ,url: XXV.help.cmdAJAX('rr')
           ,timeout: 15000
           ,success: this.onDeleteSuccess
           ,failure: this.onDeleteFailure
           ,params:{ data: todelete }
        });
      }
    },
/******************************************************************************/
  onPlaySuccess : function( response,options ) 
  { 
      var json = response.responseText;
      var o = eval("("+json+")");
      if(!o || !o.data || typeof(o.data) != 'string') {
        throw {message: "Ajax.read: Json message not found"};
      }
      if(o.param && o.param.state && o.param.state == 'success') {
          new Ext.xxv.MessageBox().msgSuccess(this.szPlayBackSuccess, o.data);
      }else {
          new Ext.xxv.MessageBox().msgFailure(this.szPlayBackFailure, o.data);
      }
  },

  onPlayFailure : function( response,options ) 
  { 
      new Ext.xxv.MessageBox().msgFailure(this.szPlayBackFailure, response.statusText);
  },

  onPlay : function( record, begin ) {
      if(this.PlayTransaction) Ext.Ajax.abort(this.PlayTransaction);
      if(record.data.isrecording != 0) {
        this.PlayTransaction = Ext.Ajax.request({
            url: XXV.help.cmdAJAX('rpv',{ data: record.data.id, '__start':begin })
           ,success: this.onPlaySuccess
           ,failure: this.onPlayFailure
        });
      }
  },
/******************************************************************************/
  onStream : function( record, begin ) {
    var item = {
       url  : XXV.help.cmdHTML('pre',{data:record.data.id,'__player':'1','__start':begin})
      ,title: record.data.fulltitle
    };

    if(!this.viewer.streamwin){
      this.viewer.streamwin = new Ext.xxv.StreamWindow(item);
    } else {
      this.viewer.streamwin.show(item);
    }
  }
  /******************************************************************************/
    ,EditItem : function( record ) {

      var item = {
         cmd:   're'
        ,id:    record.data.id
        ,title: record.data.fulltitle
      };

      if(this.viewer.formwin){
        this.viewer.formwin.close();
      }
      this.viewer.formwin = new Ext.xxv.Question(item,this.store);
    }

    ,Recover : function() {

      var item = {
         cmd:   'rru'
      };

      if(this.viewer.formwin){
        this.viewer.formwin.close();
      }
      this.viewer.formwin = new Ext.xxv.Question(item,this.store);
    }
/******************************************************************************/
    ,onUpgradeSuccess : function( response,options ) 
    { 
        Ext.MessageBox.hide();
        var o = eval("("+response.responseText+")");

        if(o && o.data && typeof(o.data) == 'string' 
             && o.param && o.param.state && o.param.state == 'success') {

            new Ext.xxv.MessageBox().msgSuccess(this.szUpgradeSuccess, o.data);
        		this.reload();

        } else {
            var msg = '';
            if(o && o.data && typeof(o.data) == 'string') {
              msg = o.data;
            }
            new Ext.xxv.MessageBox().msgFailure(this.szUpgradeFailure, msg);
        }
    }
    ,onUpgradeFailure : function( response,options ) 
    { 
        Ext.MessageBox.hide();
        new Ext.xxv.MessageBox().msgFailure(this.szUpgradeFailure, response.statusText);
    }
    ,UpgradeItem : function() {
		  Ext.Ajax.request({
		    scope: this
		   ,url: XXV.help.cmdAJAX('ru')
		   ,timeout: 120000
		   ,success: this.onUpgradeSuccess
		   ,failure: this.onUpgradeFailure
		  });

      Ext.MessageBox.show({
           title: this.szUpgradeWait
           ,msg: this.szUpgrade
           ,width:240
           ,wait:true
		       ,waitConfig:{
 			    	 interval:200
			    	,duration:119000
			    	,increment:15
			    	,fn:function() {
              Ext.MessageBox.hide();
			    	}
		       }
       });
    }
    ,reload : function() {
        this.store.load({params:{start:0, limit:configuration.pageSize}});
    }

});

function createRecordingsView(viewer,id) {

    var timefield = new Ext.form.TimeField({ 
                 id:'timeline'
                ,mode:'local'
                ,width: 100
                ,format: 'H:i:s'
                ,value: '00:00:00'
                ,increment:5
                ,minValue: new Date().clearTime()
                ,maxValue: new Date().clearTime().add('mi', (24 * 60) - 1)
                ,listeners: {
                  'expand': function(combo){
                      this.store.filterBy(function(record){ 
                        var begin = combo.minValue;
                        var end = combo.maxValue;
                        var time = Date.parseDate(record.get('text'), combo.format); 
                        return time.between(begin,end);
                      });
                    }
                }
    });

    var preview = new Ext.Panel({
        id: 'preview-recordings',
        region: 'south',
        cls:'preview',
        autoScroll: true,
        stateful:true,
        timefield : timefield,
        items: [
             {
              id: 'preview-recordings-frame',
	            xtype:'slide',
	            wrapMarginY:0,
	            wrapMarginX:0,
	            imageHeight:120, 
	            imageWidth:160, 
      		    autoWidth: true,
              listeners:{
                selected: function(slide, time, e, ele){
                  this.ownerCt.timefield.setValue(time);
                }             	
              },
	            images:[]
	            }],

        tbar: [
        {
             id:'s'
            ,iconCls: 'find-icon'
            ,tooltip: Ext.xxv.recordingsDataView.prototype.szFindReRun
            ,scope: viewer
            ,disabled:true
            ,handler: function(){ this.searchTab(this.gridRecordings.preview.record); }
        }
        ,'-'  
        ,{
             id:'re'
            ,iconCls: 'edit-icon'
            ,tooltip: Ext.xxv.recordingsDataView.prototype.szEdit
            ,scope: viewer
            ,disabled:true
            ,handler: function(){ this.gridRecordings.EditItem(this.gridRecordings.preview.record);  }
        }
        ,{
             id:'rcu'
            ,iconCls: 'cut-icon'
            ,tooltip: Ext.xxv.recordingsDataView.prototype.szCut
            ,scope: viewer
            ,disabled:true
            ,handler: function(){ this.gridRecordings.CutItem(this.gridRecordings.preview.record);  }
        }
        ,{
             id:'rr'
            ,iconCls: 'delete-icon'
            ,tooltip: Ext.xxv.recordingsDataView.prototype.szDelete
            ,scope: viewer
            ,disabled:true
            ,handler: function(){ this.gridRecordings.DeleteItem(this.gridRecordings.preview.record);  }
        }
        ,"->"
        ,{
             id:'pre'
            ,iconCls: 'stream-icon'
            ,tooltip: Ext.xxv.recordingsDataView.prototype.szStream
            ,scope: viewer
            ,disabled:true
            ,handler: function(){ this.gridRecordings.onStream(this.gridRecordings.preview.record, this.gridRecordings.preview.timefield.getValue() );  }
        }
        ,{
             id:'rpv'
            ,iconCls: 'play-icon'
            ,tooltip: Ext.xxv.recordingsDataView.prototype.szPlay
            ,scope: viewer
            ,disabled:true
            ,handler: function(){ this.gridRecordings.onPlay(this.gridRecordings.preview.record, this.gridRecordings.preview.timefield.getValue() );  }
        }
        , timefield
        ,{
             id:'recordings-shift-left'
            ,iconCls: 'x-tbar-page-prev'
            ,scope: viewer
            ,disabled:false
            ,handler: function() {
              this.gridRecordings.preview.items.items[0].Shift('left'); 
              this.gridRecordings.preview.canshift();
            }
        }
        ,{
             id:'recordings-shift-right'
            ,iconCls: 'x-tbar-page-next'
            ,scope: viewer
            ,disabled:false
            ,handler: function(){  
              this.gridRecordings.preview.items.items[0].Shift('right');
              this.gridRecordings.preview.canshift();
            }
        }
        ]
	      ,canshift : function(){
              var items = this.topToolbar.items;
              if(items) { 
                if(this.items.items[0].CanShift('right') != -1) {
                  items.get('recordings-shift-right').enable();
                } else { 
                  items.get('recordings-shift-right').disable();
                }
                if(this.items.items[0].CanShift('left') != -1) {
                  items.get('recordings-shift-left').enable();
                } else { 
                  items.get('recordings-shift-left').disable();
                }
              }
        }
	      ,content : function(record){

            if(record && this.record != record
                && record.data.isrecording 
                && this.body 
                && this.ownerCt.isVisible()) {
                  this.body.update('');
                  this.items.items[0].setvalue(record.data,true);
                  this.doLayout();
                  this.record = record;

                  this.timefield.duration = record.data.duration;
                  this.timefield.minValue=new Date().clearTime();
                  this.timefield.setValue(this.timefield.minValue);
                  this.timefield.maxValue = new Date((this.timefield.minValue.getTime())+(record.data.duration * 1000));
  
                  // Enable all toolbar buttons
                  var items = this.topToolbar.items;
                  if(items) { 
                    items.eachKey(function(key, f){if(XXV.help.cmdAllowed(key) || -1 == key.search(/shift/)) f.enable();},items); 
                  }
                  this.canshift();
                }
	      } 
        ,update : function(record) {
            if(record
                && record.data.isrecording 
                && this.body 
                && this.ownerCt.isVisible()) {
                  this.body.update('');
                  this.items.items[0].setvalue(record.data,false);
                  this.doLayout();
                  this.record = record;
            }
        }
        ,clear: function(){
            if(this) {
              if(this.body)
                this.body.update('');
              this.record = null;
              // Disable all toolbar buttons
              var items = this.topToolbar.items;
              if(items) { 
                  items.eachKey(function(key, f){f.disable();},items); 

              }
            }
        }
    });

    viewer.gridRecordings = new Ext.xxv.recordingsDataView(
                            viewer,
                            preview,
                            new Ext.xxv.recordingsStore(),
                            { id: 'recording-view-grid' });

    var tab = new Ext.xxv.Panel({
      id: id,
      iconCls:"recordings-icon",
      closable:true,
      border:false,
      layout:'border',
      stateful:true,
      hideMode:'offsets',
      items:[ viewer.gridRecordings,
            {
              id:'recording-bottom-preview',
              layout:'fit',
              items:XXV.BottomPreview ? 0 : viewer.gridRecordings.preview,
              height: 250,
              split: true,
              border:false,
              region:'south',
              hidden:XXV.BottomPreview
            }, {
              id:'recording-right-preview',
              layout:'fit',
              items:XXV.RightPreview ? 0 : viewer.gridRecordings.preview,
              border:false,
              region:'east',
              width:350,
              split: true,
              hidden:XXV.RightPreview
            }
            ]
      ,tbar:new Ext.PagingToolbar({
        	   pageSize: viewer.gridRecordings.store.autoLoad.params.limit
        	  ,store: viewer.gridRecordings.store
		      ,displayInfo: true
              ,items: [
			  {
                   id:'ru'
                  ,iconCls: 'upgrade-icon'
            	  ,tooltip: viewer.gridRecordings.szUpgrade
                  ,scope: viewer.gridRecordings
                  ,disabled:false
                  ,handler: function(){ this.UpgradeItem(); }
              },{
                   id:'rru'
                  ,iconCls: 'recover-icon'
            	  ,tooltip: viewer.gridRecordings.szRecover
                  ,scope: viewer.gridRecordings
                  ,disabled:false
                  ,handler: function(){ this.Recover(); }
              }
              ]})

    });

    viewer.add(tab);
    return tab;
}

