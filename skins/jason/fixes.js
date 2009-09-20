/*
 * jason - Javascript based skin for xxv
 * Copyright(c) 2008-2009, anbr
 * 
 * http://xxv.berlios.de/
 *
 * $Id$
 */

/* https://www.extjs.com/forum/showthread.php?t=78400 */
Ext.override(Ext.form.CheckboxGroup, {

/**
 * Gets an array of the selected {@link Ext.form.Checkbox} in the group.
 * @return {Array} An array of the selected checkboxes.
 */
getValue : function(){
    var out = [];
    this.eachItem(function(item){
        if(item.checked){
            out.push(item);
        }
    });
    return out;
}
});

/* http://extjs.com/forum/showthread.php?p=309913#post309913 */
Ext.override(Ext.form.TimeField, {
    // private
    initDate: '01/01/2008',

    // private
    initDateFormat: 'd/m/Y',

    initComponent : function(){
        Ext.form.TimeField.superclass.initComponent.call(this);

        this.minValue = this.parseDate(this.minValue) || Date.parseDate(this.initDate, this.initDateFormat).clearTime();;
        this.maxValue = this.parseDate(this.maxValue) || this.minValue.add('mi', (24 * 60) - 1);

        if(!this.store){
            var times = [],
                min = this.minValue,
                max = this.maxValue;
            while(min <= max){
                times.push([min.dateFormat(this.format)]);
                min = min.add('mi', this.increment);
            }
            this.store = new Ext.data.SimpleStore({
                fields: ['text'],
                data : times
            });
            this.displayField = 'text';
        }
    },
    
    parseDate : function(value){
        if(!value || Ext.isDate(value)){
            return value;
        }
        var v = Date.parseDate(this.initDate + ' ' + value, this.initDateFormat + ' ' + this.format);
        if(!v && this.altFormats){
            if(!this.altFormatsArray){
                this.altFormatsArray = this.altFormats.split("|");
            }
            for(var i = 0, len = this.altFormatsArray.length; i < len && !v; i++){
                v = Date.parseDate(this.initDate + ' ' + value, this.initDateFormat + ' ' + this.altFormatsArray[i]);
            }
        }
        return v;
    }    
});

