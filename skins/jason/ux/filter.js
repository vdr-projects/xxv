// vim: ts=4:sw=4:nu:fdc=4:nospell
/**
 * Search plugin for Ext.grid.GridPanel, Ext.grid.EditorGrid ver. 2.x or subclasses of them
 *
 * @author    Ing. Jozef Sakalos
 * @copyright (c) 2008, by Ing. Jozef Sakalos
 * @date      17. January 2008
 * @version   $Id: Ext.ux.grid.Search.js 11 2008-02-22 17:13:52Z jozo $
 *
 * @license Ext.ux.grid.Search is licensed under the terms of
 * the Open Source LGPL 3.0 license.  Commercial use is permitted to the extent
 * that the code/component(s) do NOT become part of another Open Source or Commercially
 * licensed development library or toolkit without explicit permission.
 * 
 * License details: http://www.gnu.org/licenses/lgpl.html
 */

Ext.namespace('Ext.ux', 'Ext.ux.grid');

/**
 * @class Ext.ux.grid.Search
 * @extends Ext.util.Observable
 * @param {Object} config configuration object
 * @constructor
 */
Ext.ux.grid.Search = function(config) {
    Ext.apply(this, config);
    Ext.ux.grid.Search.superclass.constructor.call(this);
}; // eo constructor

Ext.extend(Ext.ux.grid.Search, Ext.util.Observable, {
    /**
     * @cfg {String} searchTipText Text to display as input tooltip. Set to '' for no tooltip
     */ 
    searchTipText:'Type a text to search and press Enter'
    /**
     * @cfg {String} position Where to display the search controls. Valid values are top and bottom (defaults to bottom)
     * Corresponding toolbar has to exist at least with mimimum configuration tbar:[] for position:top or bbar:[]
     * for position bottom. Plugin does NOT create any toolbar.
     */
    ,position:'top'
    /**
     * @cfg {Number} width Width of input field in pixels (defaults to 100)
     */
    ,width:150
    /**
     * @cfg {String} xtype xtype is usually not used to instantiate this plugin but you have a chance to identify it
     */
    ,xtype:'gridsearch'
    /**
     * @cfg {Object} paramNames Params name map (defaults to {fields:'fields', query:'query'}
     */
    ,paramNames: {
         fields:'fields'
        ,all:'search'
        ,cmd:'search'
        ,query:'query'
    }
    /**
     * @cfg {String} shortcutKey Key to fucus the input field (defaults to r = Sea_r_ch). Empty string disables shortcut
     */
    ,shortcutKey:'r'
    /**
     * @cfg {String} shortcutModifier Modifier for shortcutKey. Valid values: alt, ctrl, shift (defaults to alt)
     */
    ,shortcutModifier:'alt'
    /**
     * @cfg {String} align 'left' or 'right' (defaults to 'right')
     */
    ,align:'right'
    /**
     * @cfg {Number} minLength force user to type this many character before he can make a search
     */
    ,minLength:2
    // {{{
    /**
     * private
     * @param {Ext.grid.GridPanel/Ext.grid.EditorGrid} grid reference to grid this plugin is used for
     */
    ,init:function(grid) {
        this.grid = grid;

        // do our processing after grid render
        grid.onRender = grid.onRender.createSequence(this.onRender, this);
    } // eo function init
    // }}}
    // {{{
    /**
     * private add plugin controls to <b>existing</b> toolbar and calls reconfigure
     */
    ,onRender:function() {
        var grid = this.grid;
        var tb = 'owner' == this.position ? grid.ownerCt.topToolbar : grid.topToolbar;

        // handle position
        if('right' === this.align) {
            tb.addFill();
        }
        else {
            tb.addSeparator();
        }

        // add input field (TwinTriggerField in fact)
        this.field = new Ext.form.TwinTriggerField({
             width:this.width
            ,selectOnFocus:undefined === this.selectOnFocus ? true : this.selectOnFocus
            ,trigger1Class:'x-form-clear-trigger'
            ,trigger2Class:'x-form-search-trigger'
            ,onTrigger1Click:this.onTriggerClear.createDelegate(this)
            ,onTrigger2Click:this.onTriggerSearch.createDelegate(this)
            ,minLength:this.minLength
        });

        // install event handlers on input field
        this.field.on('render', function() {
            this.field.el.dom.qtip = this.searchTipText;

            // install key map
            var map = new Ext.KeyMap(this.field.el, [{
                 key:Ext.EventObject.ENTER
                ,scope:this
                ,fn:this.onTriggerSearch
            },{
                 key:Ext.EventObject.ESC
                ,scope:this
                ,fn:this.onTriggerClear
            }]);
            map.stopEvent = true;
        }, this, {single:true});

        tb.add(this.field);

        if(tb.displayEl) {
            var size = this.field.getSize();
            tb.displayEl.setRight(10+this.width);
        }
        // keyMap
        if(this.shortcutKey && this.shortcutModifier) {
            var shortcutEl = this.grid.getEl();
            var shortcutCfg = [{
                 key:this.shortcutKey
                ,scope:this
                ,stopEvent:true
                ,fn:function() {
                    this.field.focus();
                }
            }];
            shortcutCfg[this.shortcutModifier] = true;
            this.keymap = new Ext.KeyMap(shortcutEl, shortcutCfg);
        }
    } // eo function onRender
    // }}}
    // {{{
    /**
     * private Clear Trigger click handler
     */
    ,onTriggerClear:function() {
        this.field.setValue('');
        this.field.focus();
        this.onTriggerSearch();
    } // eo function onTriggerClear
    // }}}
    // {{{
    /**
     * private Search Trigger click handler (executes the search, local or remote)
     */
    ,onTriggerSearch:function() {
        if(!this.field.isValid()) {
            return;
        }
        var val = this.field.getValue();
        var store = this.grid.store;

        // ask server to filter records
        // clear start (necessary if we have paging)
        if(store.lastOptions && store.lastOptions.params) {
            store.lastOptions.params[store.paramNames.start] = 0;
        }

        // add fields and query to baseParams of store
        delete(store.baseParams[this.paramNames.fields]);
        delete(store.baseParams[this.paramNames.query]);
        if (store.lastOptions && store.lastOptions.params) {
            delete(store.lastOptions.params[this.paramNames.fields]);
            delete(store.lastOptions.params[this.paramNames.query]);
        }
        if(val && val.length) {
            store.baseParams[this.paramNames.fields] = this.paramNames.cmd;
            store.baseParams[this.paramNames.query] = val;
        } else {
            store.baseParams[this.paramNames.fields] = this.paramNames.all;
        }

        // reload store
        store.reload();

    } // eo function onTriggerSearch
    // }}}
    // {{{
    /**
     * @param {Boolean} true to disable search (TwinTriggerField), false to enable
     */
    ,setDisabled:function() {
        this.field.setDisabled.apply(this.field, arguments);
    } // eo function setDisabled
    // }}}
    // {{{
    /**
     * Enable search (TwinTriggerField)
     */
    ,enable:function() {
        this.setDisabled(false);
    } // eo function enable
    // }}}
    // {{{
    /**
     * Enable search (TwinTriggerField)
     */
    ,disable:function() {
        this.setDisabled(true);
    } // eo function disable

}); // eo extend

// eof
