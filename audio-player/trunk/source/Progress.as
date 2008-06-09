﻿package {
	import flash.display.MovieClip;
	import flash.events.MouseEvent;
	import ProgressEvent;

	public class Progress extends MovieClip {
		private var _movingHead:Boolean;
		private var _maxPos:Number;
		
		public function Progress():void {
			bar_mc.width = 0;
			_movingHead = false;
			
			addEventListener(MouseEvent.MOUSE_DOWN, function(evt:MouseEvent) {
				_movingHead = true;
				_moveProgressBar(evt.stageX + x);
			});
			addEventListener(MouseEvent.MOUSE_MOVE, function(evt:MouseEvent) {
				if(_movingHead) _moveProgressBar(evt.stageX + x);
			});
			addEventListener(MouseEvent.MOUSE_UP, function(evt:MouseEvent) {
				var progressEvent:ProgressEvent = new ProgressEvent(bar_mc.width / track_mc.width);
				parent.dispatchEvent(progressEvent);
				_movingHead = false;
			});
			
			setMaxValue(1);
		}
		
		public function updateProgress(played:Number):void
		{
			if (!_movingHead) {
				bar_mc.width = Math.round(played * track_mc.width);
			}
		}
		
		public function setMaxValue(maxValue:Number):void
		{
			_maxPos = maxValue * track_mc.width;
		}
		
		public function resize(newWidth:Number):void
		{
			track_mc.width = newWidth - 2;
			border_mc.width = newWidth;
		}
	
		private function _moveProgressBar(xMouse:Number):void {
			var newPos:Number = xMouse - 1;
			if (newPos < 0) {
				newPos = 0;
			} else if (newPos > _maxPos) {
				newPos = _maxPos;
			}
			bar_mc.width = newPos;
		}
	}
}