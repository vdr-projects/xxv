<?% IF global.bodyinc.defined && global.bodyinc == 1 && ! global.shutter.defined; global.shutter = 1 %?>
<script type="text/javascript">
<!--
function popupkeypress(e) {
    var KeyID = (window.event) ? event.keyCode : e.keyCode;
    if(KeyID == 27) {    closeit();  } //ESC
}
document.onkeypress = popupkeypress;
//-->
</script>
    <div id="shutter">
        <a href="javascript:closeit()">
            <img src="images/close.gif" alt="" />
        </a>
    </div>
<?% END %?>
