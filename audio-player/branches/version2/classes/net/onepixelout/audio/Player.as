import mx.utils.Delegate;
import net.onepixelout.audio.*;
import com.freesome.events.LcBroadcast;

/**
* The definitive AS2 mp3 player from 1 Pixel Out
* @author Martin Laine
*/
class net.onepixelout.audio.Player
{
	private var _playlist:Playlist; // Current loaded playlist
	private var _loadingPlaylist:Boolean;

	private var _playhead:Sound; // The player head
	private var _volume:Number;
	
	// For fading volume when pausing
	private var _fadeVolume:Number;
	private var _fadeClearID:Number;
	
	// State
	public var state:Number;

	// State constants
	static var NOTFOUND:Number = -1;
	static var INITIALISING:Number = 0;
	static var STOPPED:Number = 1;
	static var PAUSED:Number = 2;
	static var PLAYING:Number = 3;
	
	static var _isBuffering:Boolean;
	static var _isConnecting:Boolean;

	public var duration:Number; // Current song duration (in ms)
	public var position:Number; // Current song position (in ms)
	public var loaded:Number; // Percentage of song loaded (0 to 1)
	public var played:Number; // Percentage of song played (0 to 1)
	
	private var _recordedPosition:Number; // When paused, play head position is stored here
	private var _startPlaying:Boolean;
	
	// Buffering detection variables
	private var _playCounter:Number;
	private var _lastPosition:Number;
	
	private var _clearID:Number; // In case we need to stop the periodical function
	
	private var _lcBroadcaster:LcBroadcast;
	private var _playOnInit:Boolean;
	
	public var addListener:Function;
	public var removeListener:Function;
	private var broadcastMessage:Function;
	
	private var _options:Object = {
		initialVolume:70,
		enableCycling:true
	};
	
	function Player(options:Object)
	{
		// Turn Player into broadcaster
		AsBroadcaster.initialize(this);
		
		// Write options to internal options structure
		if(options != undefined) _setOptions(options);
		
		// Initialise properties
		_volume = _options.initialVolume;
		this.state = INITIALISING;
		_loadingPlaylist = false;
		_playOnInit = false;
		_reset();
		
		// Run watcher every 10ms
		_clearID = setInterval(this, "_watch", 50);
		
		// Create listener for local connection broadcaster
		var listen = new Object();
		listen.onBroadcast = Delegate.create(this, _receiveMessage);
		listen.onInit = Delegate.create(this, _activate);
		
		// Create local connection broadcaster
		_lcBroadcaster = new LcBroadcast();
		
		// Add the listener
		_lcBroadcaster.addListener(listen);
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
		this.duration = 0;
		this.position = 0;
		this.loaded = 0;
		this.played = 0;
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
		if(this.state == PLAYING) return;
		
		// If player is still initialising, wait for it
		if(this.state == INITIALISING)
		{
			_playOnInit = true;
			return;
		}
		
		_setBufferTime(_recordedPosition);
		
		// Load current song and get reference to the sound object
		var currentSong:Song = this.getCurrentSong();
		_playhead = currentSong.load( (_recordedPosition == 0) );
		
		// Setup onSoundComplete event
		if(_playhead.onSoundComplete == undefined) _playhead.onSoundComplete = Delegate.create(this, next);
		
		this.setVolume();
		
		if(_recordedPosition > 0) _playhead.start(Math.round(_recordedPosition / 1000));
		
		if(this.state == STOPPED) _isConnecting = true;
		this.state = PLAYING;

		// Broadcast message to other players
		_lcBroadcaster.broadcast({msg:"pause", id:_lcBroadcaster.internalID});
	}
	
	/**
	* Pauses the player
	*/
	public function pause():Void
	{
		// Pause button is also play button when player is paused
		if(this.state == PAUSED)
		{
			this.play();
			return;
		}
		
		// If player isn't playing, do nothing
		if(this.state < PLAYING) return;
		
		// Start a fade out
		_fadeVolume  = _volume;
		_fadeClearID = setInterval(this, "_fadeOut", 50);
		
		this.state = PAUSED;
	}

	/**
	* Stops the player (also pauses download)
	*/
	public function stop():Void
	{
		_playhead.stop();
		_playhead = this.getCurrentSong().unLoad();
		this.state = STOPPED;
		_reset();
	}

	/**
	* Moves player head to a new position
	* @param newPosition a number between 0 and 1
	*/
	public function moveHead(newPosition:Number):Void
	{
		// Player in paused state: simply record the new position
		if(this.state == PAUSED) _recordedPosition = this.duration * newPosition;
		else
		{
			// Otherwise, stop player, calculate new buffer time and restart player
			_playhead.stop();
			_setBufferTime(duration * newPosition);
			_playhead.start(Math.round((duration * newPosition) / 1000));
		}
	}

	/**
	* Moves to next track in playlist
	* If player is playing, start the track
	*/
	public function next():Void
	{
		// Ignore if player is still initialising
		if(this.state == INITIALISING) return;
		
		var startPlaying:Boolean = (this.state == PLAYING);

		// This stops any downloading that may still be going on
		this.stop();
		
		_playlist.next();
		if(startPlaying) this.play();
	}

	/**
	* Moves to previous track in playlist
	* If player is playing, start the track
	*/
	public function previous():Void
	{
		// Ignore if player is still initialising
		if(this.state == INITIALISING) return;
		
		var startPlaying:Boolean = (this.state == PLAYING);
		
		// This stops any downloading that may still be going on
		this.stop();
		
		_playlist.previous();
		if(startPlaying) this.play();
	}

	/**
	* Sets the player volume
	* @param newVolume number between 0 and 100
	*/
	public function setVolume(newVolume:Number):Void
	{
		// If we have a new value for volume, set it
		if(newVolume != undefined) _volume = newVolume;
		// Set the player volume
		_playhead.setVolume(_volume);
	}

	/**
	* Fades player out
	*/
	private function _fadeOut():Void
	{
		_fadeVolume -= 8;
		if(_fadeVolume <= 0)
		{
			clearInterval(_fadeClearID);
			var currentSong:Song = this.getCurrentSong();
			_recordedPosition = _playhead.position;
			_playhead.stop();
			if(_options.pauseDownload) _playhead = currentSong.unLoad();
		}
		else _playhead.setVolume(_fadeVolume);
	}
	
	/**
	* Updates playhead statistics (loaded, played, duration and position)
	* Also triggers song information update (when ID3 is available)
	*/
	private function _updateStats():Void
	{
		if(_playhead.getBytesTotal() > 0)
		{
			// Flash has started downloading the file
			_isConnecting = false;
			
			// Get current song
			var currentSong:Song = this.getCurrentSong();
			
			// If current song is fully loaded, no need to calculate loaded and duration
			if(currentSong.isFullyLoaded()) {
				this.loaded = 1;
				this.duration = _playhead.duration;
			}
			else
			{
				this.loaded = _playhead.getBytesLoaded() / _playhead.getBytesTotal();
			
				// Get real duration because the sound is fully loaded
				if(this.loaded == 1) this.duration = _playhead.duration;
				// Get duration from ID3 tag
				else if(_playhead.id3.TLEN != undefined) this.duration = parseInt(_playhead.id3.TLEN);
				// This is an estimate
				else this.duration = (1 / this.loaded) * _playhead.duration;
			}
			
			// Update position and played values if playhead is reading
			if(_playhead.position > 0)
			{
				this.position = _playhead.position;
				this.played = this.position / this.duration;
			}
			
			// Update song info if ID3 tags are available
			if(!currentSong.isID3Loaded() && _playhead.id3.songname.length > 0) currentSong.setInfo();
		}
	}
	
	private function _watch():Void
	{
		// Get current song
		var currentSong:Song = this.getCurrentSong();
		
		// If the mp3 file doesn't exit
		if(this.state > NOTFOUND && !_loadingPlaylist && !currentSong.exists())
		{
			// Reset player
			_reset();
			this.state = NOTFOUND;
			return;
		}
		
		_updateStats();
		
		// Buffering detection
		if(this.state == PLAYING)
		{
			if(++_playCounter == 10)
			{
				_playCounter = 0;
				_isBuffering = (this.position == _lastPosition);
				_lastPosition = this.position;
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
	* Sets the buffer time to a maximum of 5 seconds.
	* 
	* @param newPosition Position of playhead
	*/
	private function _setBufferTime(newPosition:Number):Void
	{
		// No buffering needed if file is fully loaded
		if(this.getCurrentSong().isFullyLoaded())
		{
			_root._soundbuftime = 0;
			return;
		}
		
		// Otherwise, look at how much audio is playable and set buffer accordingly
		
		var currentBuffer:Number = Math.round(((this.loaded * this.duration) - newPosition) / 1000);
		
		if(currentBuffer >= 5) _root._soundbuftime = 0;
		else _root._soundbuftime = 5 - currentBuffer;
	}
	
	/**
	* Loads a list of mp3 files onto a playlist
	* @param	songFileList
	*/
	public function loadPlaylist(songFileList:String):Void
	{
		_playlist = new Playlist(_options.enableCycling);
		_playlist.loadFromList(songFileList);
	}
	
	/*public function loadXMLPlaylist(xmlURL:String):Void
	{
		if(xmlURL == undefined) xmlURL = "playlist.xml";
		_playlistXML = new XML();
		_playlistXML.ignoreWhite = true;
		_playlistXML.onLoad = Delegate.create(this, _receivePlaylistXML);
		_playlistXML.load(xmlURL);
		_loadingPlaylist = true;
	}
	
	private function _receivePlaylistXML(success:Boolean):Void
	{
		if(!success)
		{
			trace("XML not found");
			this.state = NOTFOUND;
			return;
		}
		_playlist = new Playlist(_options.enableCycling);
		_playlist.loadFromXML(_playlistXML);
		_loadingPlaylist = false;
		if(this.state != INITIALISING && _playOnInit)
		{
			this.play();
			_playOnInit = false;
		}
	}*/
	
	/**
	* Returns current song from the playlist
	* @return the current song object
	*/
	public function getCurrentSong():Song
	{
		return _playlist.getCurrent();
	}

	/**
	* Activates player when local connection broadcaster has initialised
	*/
	private function _activate():Void
	{
		if(this.state == INITIALISING) this.state = STOPPED;
		if(_playOnInit && !_loadingPlaylist)
		{
			this.play();
			_playOnInit = false;
		}
	}
	
	/**
	* Receives messages from local connection broadcaster
	* @param parameters contains id (th broadcaster id and the msg string)
	*/
	private function _receiveMessage(parameters:Object):Void
	{
		// Ignore messages from this player
		if(parameters.id == _lcBroadcaster.internalID) return;
		switch(parameters.msg)
		{
			case "pause":
				if(this.state == PLAYING) this.pause();
				break;
				
			default:
				break;
		}
	}
}