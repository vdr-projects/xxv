/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

Ext.xxv.storeChannels = function() {
    return new Ext.data.Store({
            autoLoad: true,
            reader: new Ext.xxv.jsonReader({
                        fields: [
                                  {name: 'id', type: 'string'},
                                  {name: 'name', type: 'string'},
                                  {name: 'frequency', type: 'int'},
                                  {name: 'parameter', type: 'string'},
                                  {name: 'source', type: 'string'},
                                  {name: 'srate', type: 'string'},
                                  {name: 'vpid', type: 'string'},
                                  {name: 'apid', type: 'string'},
                                  {name: 'tpid', type: 'string'},
                                  {name: 'ca', type: 'string'},
                                  {name: 'sid', type: 'string'},
                                  {name: 'nid', type: 'string'},
                                  {name: 'tid', type: 'string'},
                                  {name: 'rid', type: 'string'},
                                  {name: 'group', type: 'string'},
                                  {name: 'position', type: 'int'},
                                  {name: 'grpname', type: 'string'}
                                ]
                    }),
            proxy : new Ext.data.HttpProxy({
                url: XXV.help.cmdAJAX('cl')
               ,method: 'GET'
            })
//          sortInfo:{field:'position', direction:'ASC'}
    });

};

/******************************************************************************/
Ext.xxv.ChannelsCombo = function(config){
    Ext.apply(this, config);
    if(!this.id){
        this.id = Ext.id();
    }
    this.renderer = this.renderer.createDelegate(this);
};

Ext.xxv.ChannelsCombo.prototype ={
    init : function(grid){
/*      this.grid = grid;
        this.grid.on('render', function(){
            var view = this.grid.getView();
        }, this);*/
    },
    renderer: function(value, p, record) {

      for(var i = 0, len = this.store.data.length; i < len; i++){
        var rec = this.store.getAt(i);
        if(rec.data.position == value) {
          return rec.data.name;
        }
      }
    	return record.data.channel;
    }
};
