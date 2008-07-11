﻿import net.onepixelout.audio.*;
import mx.utils.Delegate;

/**
* The definitive AS2 mp3 player from 1 Pixel Out
* @author Martin Laine
*/
class net.onepixelout.audio.Player
{
	private var _playlist:Playlist; // Current loaded playlist
	
	private var _playhead:Sound; // The player head
	private var _volume:Number;
	
	// For fading volume when pausing
	private var _fadeVolume:Number;
	private var _fadeClearID:Number;
	
	// State
	private var _state:Number;

	// State constants
	static public var NOTFOUND:Number = -1;
	static public var STOPPED:Number = 1;
	static public var PAUSED:Number = 2;
	static public var PLAYING:Number = 3;
	
	private var _isBuffering:Boolean;
	private var _isConnecting:Boolean;

	private var _duration:Number; // Current track duration (in ms)
	private var _position:Number; // Current track position (in ms)
	private var _loaded:Number; // Percentage of track loaded (0 to 1)
	private var _played:Number; // Percentage of track played (0 to 1)
	
	private var _recordedPosition:Number; // When paused, play head position is stored here
	private var _startPlaying:Boolean;
	
	// Buffering detection variables
	private var _playCounter:Number;
	private var _lastPosition:Number;
	
	private var _clearID:Number; // In case we need to stop the periodical function
	private var _delayID:Number; // For calling a method with a delay
	
	private var broadcastMessage:Function;
	public var addListener:Function;
	public var removeListener:Function;

	// Options structure
	private var _options:Object = {
		playerID:"",
		initialVolume:60,
		enableCycling:true,
		syncVolumes:true,
		killDownload:true,
		checkPolicy:false,
		bufferTime:5
	};
	
	/**
	* Constructor
	* @param options these get written to the internal _options structure
	*/
	function Player(options:Object)
	{
		AsBroadcaster.initialize(this);
		
		// Write options to internal options structure
		if(options != undefined) _setOptions(options);
		
		// Initialise properties
		_volume = _options.initialVolume;
		_state = STOPPED;
		_reset();
		
		// Run watcher every 10ms
		_clearID = setInterval(this, "_watch", 50);
	}
	
	/**
	* Writes options object to internal options struct
	* @param	options
	*/
	private function _setOptions(options:Object):Void
	{
		for(var key:String in options) _options[key] = options[key];
	}
	
	/**
	* Resets player
	*/
	private function _reset():Void
	{
		_duration = 0;
		_position = 0;
		_loaded = 0;
		_played = 0;
		_isBuffering = false;
		_isConnecting = false;
		_recordedPosition = 0;
		_startPlaying = false;
		_lastPosition = 0;
		_playCounter = 0;
	}
	
	/**
	* Starts the player
	*/
	public function play():Void
	{
		// If already playing, do nothing
		if(_state == PLAYING) return;
		
		_setBufferTime(_recordedPosition);
		
		// Load current track and get reference to the sound object
		var currentTrack:Track = this.getCurrentTrack();
		_playhead = currentTrack.load(_options.checkPolicy);
		
		// Setup onSoundComplete event
		if(_playhead.onSoundComplete == undefined) _playhead.onSoundComplete = Delegate.create(this, next);
		
		if(_state == STOPPED) _isConnecting = true;
		_state = PLAYING;

		this.setVolume();
		
		_playhead.start(Math.floor(_recordedPosition / 1000));
		
		// Update stats now (don't wait for watcher to kick in)
		_updateStats();
	}
	
	/**
	* Pauses the player
	*/
	public function pause():Void
	{
		// Pause button is also play button when player is paused
		if(_state == PAUSED)
		{
			this.play();
			return;
		}
		
		// If player isn't playing, do nothing
		if(_state < PLAYING) return;
		
		// Start a fade out
		_fadeVolume  = _volume;
		_fadeClearID = setInterval(this, "_fadeOut", 50);
		
		_state = PAUSED;
	}

	/**
	* Stops the player (also pauses download)
	*/
	public function stop(broadcast:Boolean):Void
	{
		if(broadcast == undefined) broadcast = true;
		
		// Tell anyone interested that the player has stopped
		if(broadcast) broadcastMessage("onStop");
		
		// Stop playhead and unload track (stops download);
		_playhead.stop();
		this.getCurrentTrack().unLoad();
		_playhead = null;
		
		_state = STOPPED;
		_reset();
	}

	/**
	* Moves player head to a new position
	* @param newPosition a number between 0 and 1
	*/
	public function moveHead(newHeadPosition:Number):Void
	{
		// Ignore if player is not playing or paused
		if(_state < PAUSED) return;
		
		var newPosition:Number = _duration * newHeadPosition;
		
		// Player in paused state: simply record the new position
		if(_state == PAUSED) _recordedPosition = newPosition;
		else
		{
			// Otherwise, stop player, calculate new buffer time and restart player
			_playhead.stop();
			_setBufferTime(newPosition);
			_playhead.start(Math.floor(newPosition / 1000));
		}
		
		// Update stats now (don't wait for watcher to kick in)
		_updateStats();
	}

	/**
	* Moves to next track in playlist
	* If player is playing, start the track
	*/
	public function next():Void
	{
		var startPlaying:Boolean = (_state == PLAYING || _state == NOTFOUND);

		if(_playlist.next() != null && startPlaying)
		{
			this.stop(false);
			this.play();
		}
		else this.stop(true);
	}

	/**
	* Moves to previous track in playlist
	* If player is playing, start the track
	*/
	public function previous():Void
	{
		var startPlaying:Boolean = (_state == PLAYING);
		
		if(_playlist.previous() != null && startPlaying)
		{
			this.stop(false);
			this.play();
		}
		else this.stop(false);
	}

	/**
	* Sets the player volume
	* @param newVolume number between 0 and 100
	* @param broadcast if true, a setvolume message is broadcast to any other players to synchronise volumes
	*/
	public function setVolume(newVolume:Number, broadcast:Boolean):Void
	{
		clearInterval(_delayID);
		
		//if(broadcast == undefined) broadcast = false;
		
		// If we have a new value for volume, set it
		if(newVolume != undefined) _volume = newVolume;
		// Set the player volume
		if(_state > STOPPED) _playhead.setVolume(_volume);
	}
	
	/**
	* Returns a snapshot of the current state of the player
	* @return a structure of values describing the current state
	*/
	public function getState():Object
	{
		var result:Object = new Object();
		
		result.state = _state;
		result.buffering = _isBuffering;
		result.connecting = _isConnecting;
		result.loaded = _loaded;
		result.played = _played;
		result.duration = _duration;
		result.position = _position;
		result.volume = _volume;
		result.trackIndex = _playlist.getCurrentIndex();
		result.hasNext = _playlist.hasNext();
		result.hasPrevious = _playlist.hasPrevious();
		result.trackCount = _playlist.length;
		
		result.trackInfo = this.getCurrentTrack().getInfo();
		
		return result;
	}

	/**
	* Fades player out
	*/
	private function _fadeOut():Void
	{
		_fadeVolume -= 20;
		if(_fadeVolume <= 20)
		{
			clearInterval(_fadeClearID);
			_recordedPosition = _playhead.position;
			_playhead.stop();
		}
		else _playhead.setVolume(_fadeVolume);
	}
	
	/**
	* Updates playhead statistics (loaded, played, duration and position)
	* Also triggers track information update (when ID3 is available)
	*/
	private function _updateStats():Void
	{
		if(_state > STOPPED && _playhead.getBytesTotal() > 0)
		{
			// Flash has started downloading the file
			_isConnecting = false;
			
			// Get current track
			var currentTrack:Track = this.getCurrentTrack();
			
			// If current track is fully loaded, no need to calculate loaded and duration
			if(currentTrack.isFullyLoaded()) {
				_loaded = 1;
				_duration = _playhead.duration;
			}
			else
			{
				_loaded = _playhead.getBytesLoaded() / _playhead.getBytesTotal();
			
				// Get real duration because the sound is fully loaded
				if(_loaded == 1) _duration = _playhead.duration;
				// Get duration from ID3 tag
				else if(_playhead.id3.TLEN != undefined) _duration = parseInt(_playhead.id3.TLEN);
				// This is an estimate
				else _duration = (1 / _loaded) * _playhead.duration;
			}
			
			// Update position and played values if playhead is reading
			if(_playhead.position > 0)
			{
				_position = _playhead.position;
				_played = _position / _duration;
			}
			
			// Update track info if ID3 tags are available
			if(!currentTrack.isID3Loaded() && _playhead.id3.songname.length > 0) currentTrack.setInfo();
		}
	}
	
	/**
	* Watches player state. This method is run periodically (see constructor)
	*/
	private function _watch():Void
	{
		// Get current track
		var currentTrack:Track = this.getCurrentTrack();
		
		// If the mp3 file doesn't exit
		if(_state > NOTFOUND && !currentTrack.exists())
		{
			// Reset player
			_reset();
			_state = NOTFOUND;
			return;
		}
		
		// Update statistics
		_updateStats();
		
		// Buffering detection
		if(_state == PLAYING)
		{
			if(++_playCounter == 2)
			{
				_playCounter = 0;
				_isBuffering = (_position == _lastPosition);
				_lastPosition = _position;
			}
		}
	}
	
	public function isBuffering():Boolean
	{
		return _isBuffering;
	}
	public function isConnecting():Boolean
	{
		return _isConnecting;
	}

	/**
	* Sets the buffer time to a maximum of 5 seconds (or whatever the bufferTime option is set to).
	* 
	* @param newPosition Position of playhead
	*/
	private function _setBufferTime(newPosition:Number):Void
	{
		// No buffering needed if file is fully loaded
		if(this.getCurrentTrack().isFullyLoaded())
		{
			_root._soundbuftime = 0;
			return;
		}
		
		// Otherwise, look at how much audio is playable and set buffer accordingly
		var currentBuffer:Number = Math.round(((_loaded * _duration) - newPosition) / 1000);
		
		if(currentBuffer >= _options.bufferTime) _root._soundbuftime = 0;
		else _root._soundbuftime = _options.bufferTime - currentBuffer;
	}
	
	/**
	* Loads a list of mp3 files onto a playlist
	* @param trackFileList
	*/
	public function loadPlaylist(trackFileList:String, titleList:String, artistList:String):Void
	{
		if(titleList == undefined) titleList = "";
		if(artistList == undefined) artistList = "";
		_playlist = new Playlist(_options.enableCycling);
		_playlist.loadFromList(trackFileList, titleList, artistList);
		_reset();
	}
	
	/**
	* Returns the number of tracks in the playlist
	* @return the number of tracks
	*/
	public function getTrackCount():Number
	{
		return _playlist.length;
	}

	/**
	* Returns current track from the playlist
	* @return the current track object
	*/
	public function getCurrentTrack():Track
	{
		return _playlist.getCurrent();
	}
}