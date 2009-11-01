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


/* http://www.extjs.com/forum/showthread.php?t=78223 */
Ext.override(Ext.layout.VBoxLayout, {
    onLayout : function(ct, target){
        Ext.layout.VBoxLayout.superclass.onLayout.call(this, ct, target);
        var cs = this.getItems(ct), cm, ch, margin,
            size = this.getTargetSize(target),
            w = size.width - target.getPadding('lr'),
            h = size.height - target.getPadding('tb') - this.scrollOffset,
            l = this.padding.left, t = this.padding.top,
            isStart = this.pack == 'start',
            isRestore = ['stretch', 'stretchmax'].indexOf(this.align) == -1,
            stretchWidth = w - (this.padding.left + this.padding.right),
            extraHeight = 0,
            maxWidth = 0,
            totalFlex = 0,
            flexHeight = 0,
            usedHeight = 0;
        Ext.each(cs, function(c){
            cm = c.margins;
            totalFlex += c.flex || 0;
            ch = c.getHeight();
            margin = cm.top + cm.bottom;
            extraHeight += ch + margin;
            flexHeight += margin + (c.flex ? 0 : ch);
            maxWidth = Math.max(maxWidth, c.getWidth() + cm.left + cm.right);
        });
        extraHeight = h - extraHeight - this.padding.top - this.padding.bottom;
        var th = flexHeight + this.padding.top + this.padding.bottom;
        if(h < th){
            h = th;
            w -= this.scrollOffset;
            stretchWidth -= this.scrollOffset;
        }
        var innerCtWidth = maxWidth + this.padding.left + this.padding.right;
        switch(this.align){
            case 'stretch':
                this.innerCt.setSize(w, h);
                break;
            case 'stretchmax':
            case 'left':
                this.innerCt.setSize(innerCtWidth, h);
                break;
            case 'center':
                this.innerCt.setSize(w = Math.max(w, innerCtWidth), h);
                break;
        }
        var availHeight = Math.max(0, h - this.padding.top - this.padding.bottom - flexHeight),
            leftOver = availHeight,
            heights = [],
            restore = [],
            idx = 0,
            availableWidth = Math.max(0, w - this.padding.left - this.padding.right);
        Ext.each(cs, function(c){
            if(isStart && c.flex){
                ch = Math.floor(availHeight * (c.flex / totalFlex));
                leftOver -= ch;
                heights.push(ch);
            }
        });
        if(this.pack == 'center'){
            t += extraHeight ? extraHeight / 2 : 0;
        }else if(this.pack == 'end'){
            t += extraHeight;
        }
        Ext.each(cs, function(c){
            cm = c.margins;
            t += cm.top;
            c.setPosition(l + cm.left, t);
            if(isStart && c.flex){
                ch = Math.max(0, heights[idx++] + (leftOver-- > 0 ? 1 : 0));
                if(isRestore){
                    restore.push(c.getWidth());
                }
                c.setSize(availableWidth, ch);
            }else{
                ch = c.getHeight();
            }
            t += ch + cm.bottom;
        });
        idx = 0;
        Ext.each(cs, function(c){
            cm = c.margins;
            if(this.align == 'stretch'){
                c.setWidth((stretchWidth - (cm.left + cm.right)).constrain(
                    c.minWidth || 0, c.maxWidth || 1000000));
            }else if(this.align == 'stretchmax'){
                c.setWidth((maxWidth - (cm.left + cm.right)).constrain(
                    c.minWidth || 0, c.maxWidth || 1000000));
            }else{
                if(this.align == 'center'){
                    var diff = availableWidth - (c.getWidth() + cm.left + cm.right);
                    if(diff > 0){
                        c.setPosition(l + cm.left + (diff/2), c.y);
                    }
                }
                if(isStart && c.flex){
                    c.setWidth(restore[idx++]);
                }
            }
        }, this);
    }
});
Ext.override(Ext.layout.HBoxLayout, {
    onLayout : function(ct, target){
        Ext.layout.HBoxLayout.superclass.onLayout.call(this, ct, target);
        var cs = this.getItems(ct), cm, cw, margin,
            size = this.getTargetSize(target),
            w = size.width - target.getPadding('lr') - this.scrollOffset,
            h = size.height - target.getPadding('tb'),
            l = this.padding.left, t = this.padding.top,
            isStart = this.pack == 'start',
            isRestore = ['stretch', 'stretchmax'].indexOf(this.align) == -1,
            stretchHeight = h - (this.padding.top + this.padding.bottom),
            extraWidth = 0,
            maxHeight = 0,
            totalFlex = 0,
            flexWidth = 0,
            usedWidth = 0;
        Ext.each(cs, function(c){
            cm = c.margins;
            totalFlex += c.flex || 0;
            cw = c.getWidth();
            margin = cm.left + cm.right;
            extraWidth += cw + margin;
            flexWidth += margin + (c.flex ? 0 : cw);
            maxHeight = Math.max(maxHeight, c.getHeight() + cm.top + cm.bottom);
        });
        extraWidth = w - extraWidth - this.padding.left - this.padding.right;
        var tw = flexWidth + this.padding.left + this.padding.right;
        if(w < tw){
            w = tw;
            h -= this.scrollOffset;
            stretchHeight -= this.scrollOffset;
        }
        var innerCtHeight = maxHeight + this.padding.top + this.padding.bottom;
        switch(this.align){
            case 'stretch':
                this.innerCt.setSize(w, h);
                break;
            case 'stretchmax':
            case 'top':
                this.innerCt.setSize(w, innerCtHeight);
                break;
            case 'middle':
                this.innerCt.setSize(w, h = Math.max(h, innerCtHeight));
                break;
        }
        var availWidth = Math.max(0, w - this.padding.left - this.padding.right - flexWidth),
            leftOver = availWidth,
            widths = [],
            restore = [],
            idx = 0,
            availableHeight = Math.max(0, h - this.padding.top - this.padding.bottom);
        Ext.each(cs, function(c){
            if(isStart && c.flex){
                cw = Math.floor(availWidth * (c.flex / totalFlex));
                leftOver -= cw;
                widths.push(cw);
            }
        });
        if(this.pack == 'center'){
            l += extraWidth ? extraWidth / 2 : 0;
        }else if(this.pack == 'end'){
            l += extraWidth;
        }
        Ext.each(cs, function(c){
            cm = c.margins;
            l += cm.left;
            c.setPosition(l, t + cm.top);
            if(isStart && c.flex){
                cw = Math.max(0, widths[idx++] + (leftOver-- > 0 ? 1 : 0));
                if(isRestore){
                    restore.push(c.getHeight());
                }
                c.setSize(cw, availableHeight);
            }else{
                cw = c.getWidth();
            }
            l += cw + cm.right;
        });
        idx = 0;
        Ext.each(cs, function(c){
            var cm = c.margins;
            if(this.align == 'stretch'){
                c.setHeight((stretchHeight - (cm.top + cm.bottom)).constrain(
                    c.minHeight || 0, c.maxHeight || 1000000));
            }else if(this.align == 'stretchmax'){
                c.setHeight((maxHeight - (cm.top + cm.bottom)).constrain(
                    c.minHeight || 0, c.maxHeight || 1000000));
            }else{
                if(this.align == 'middle'){
                    var diff = availableHeight - (c.getHeight() + cm.top + cm.bottom);
                    if(diff > 0){
                        c.setPosition(c.x, t + cm.top + (diff/2));
                    }
                }
                if(isStart && c.flex){
                    c.setHeight(restore[idx++]);
                }
            }
        }, this);
    }
});

/* http://www.extjs.com/forum/showthread.php?t=73615 */
Ext.override(Ext.menu.Menu, {
    show: function(el, pos, parentMenu) {
        if (this.floating) {
            this.parentMenu = parentMenu;
            if (!this.el) {
                this.render();
                this.doLayout(false, true);
            }
            //if(this.fireEvent('beforeshow', this) !== false){
            this.showAt(this.el.getAlignToXY(el, pos || this.defaultAlign, this.defaultOffsets), parentMenu, false);
            //}
        } else {
            Ext.menu.Menu.superclass.show.call(this);
        }
    },
    showAt: function(xy, parentMenu, _e) {
        if (this.fireEvent('beforeshow', this) !== false) {
            this.parentMenu = parentMenu;
            if (!this.el) {
                this.render();
            }
            if (_e !== false) {
                xy = this.el.adjustForConstraints(xy);
            }
            this.el.setXY(xy);
            if (this.enableScrolling) {
                this.constrainScroll(xy[1]);
            }
            this.el.show();
            Ext.menu.Menu.superclass.onShow.call(this);
            if (Ext.isIE) {
                this.layout.doAutoSize();
                if (!Ext.isIE8) {
                    this.el.repaint();
                }
            }
            this.hidden = false;
            this.focus();
            this.fireEvent("show", this);
        }
    }
});
