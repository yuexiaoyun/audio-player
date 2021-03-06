﻿import mx.utils.Delegate;

class Volume extends MovieClip
{
	public var icon_mc:MovieClip;
	public var control_mc:MovieClip;
	public var background_mc:MovieClip;
	public var button_mc:MovieClip;
	
	public var realWidth:Number;
	
	private var _settingVolume:Boolean;
	private var _initialMaskPos:Number;

	public var addListener:Function;
	public var removeListener:Function;
	private var broadcastMessage:Function;

	private var _clearID:Number;
	
	private var _rtl:Boolean = false;
	
	/**
	 * Constructor
	 */
	function Volume()
	{
		AsBroadcaster.initialize(this);

		control_mc._alpha = 0;
		this.button_mc._visible = false;
		icon_mc._alpha = 100;
		
		_settingVolume = false;
		
		_initialMaskPos = this.control_mc.mask_mc._x;
		
		this.realWidth = this.background_mc._width;
		
		this.button_mc.onPress = Delegate.create(this, function() {
			this._settingVolume = true;
			this._moveVolumeBar();
		});
		this.button_mc.onMouseMove = Delegate.create(this, function() {
			if(this._settingVolume)
			{
				this._moveVolumeBar();
				this.broadcastMessage("onSetVolume", this._getValue(), false);
			}
		});
		this.button_mc.onRelease = this.button_mc.onReleaseOutside = Delegate.create(this, function() {
			this._settingVolume = false;
			this._moveVolumeBar();
			this.broadcastMessage("onSetVolume", this._getValue(), true);
		});
	}
	
	/**
	 * Updates volume
	 */
	public function update(volume:Number):Void
	{
		if(!_settingVolume) this.control_mc.mask_mc._x = _initialMaskPos + Math.round(this.control_mc.track_mc._width * volume / 100);
	}
	
	private function _moveVolumeBar():Void
	{
		if(this.control_mc.track_mc._xmouse > this.control_mc.track_mc._width) this.control_mc.mask_mc._x = _initialMaskPos + this.control_mc.track_mc._width;
		else if(this.control_mc.track_mc._xmouse < 0) this.control_mc.mask_mc._x = _initialMaskPos;
		else this.control_mc.mask_mc._x = _initialMaskPos + this.control_mc.track_mc._xmouse;
	}
	
	/**
	 * Returns the current position of the volume slider as a percentage
	 * @return	number between 0 and 100
	 */
	private function _getValue():Number
	{
		return Math.round((this.control_mc.mask_mc._x - _initialMaskPos) / this.control_mc.track_mc._width * 100);
	}
		
	public function toggleControl(toggle:Boolean, immediate:Boolean):Void
	{
		clearInterval(_clearID);
		if(toggle) _clearID = setInterval(this, "_animate", 41, 100, 0, _rtl ? 11 : 6);
		else _clearID = setInterval(this, "_animate", 41, 0, 100, _rtl ? 21 : 16);
	}
	
	private function _animate(targetControl:Number, targetIcon:Number, targetIconX:Number):Void
	{
		var dAlphaControl:Number = targetControl - control_mc._alpha;
		var dAlphaIcon:Number = targetIcon - icon_mc._alpha;
		var dAlphaIconX:Number = targetIconX - icon_mc._x;
		var speed:Number = 0.3;
		
		dAlphaControl = dAlphaControl * speed;
		dAlphaIcon = dAlphaIcon * speed;
		dAlphaIconX = dAlphaIconX * speed;

		// Stop animation when we are at less than a pixel from the target
		if(Math.abs(dAlphaControl) < 1)
		{
			// Position the control element to the exact target position
			control_mc._alpha = targetControl;
			icon_mc._alpha = targetIcon;
			icon_mc._x = targetIconX;
			
			button_mc._visible = (control_mc._alpha == 100);
			
			clearInterval(_clearID);
			return;
		}
		
		control_mc._alpha += dAlphaControl;
		icon_mc._alpha += dAlphaIcon;
		icon_mc._x += dAlphaIconX;
	}
	
	public function flip():Void {
		_rtl = true;
		
		this.background_mc._rotation = 180;
		this.background_mc._y += this.background_mc._height;
		this.background_mc._x += this.background_mc._width;
		this.control_mc._x += 5;
		this.icon_mc._x += 5;
		
	}
}