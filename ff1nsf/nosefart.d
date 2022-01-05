/++
	Bindings to the C nosefart library which processes NSF files
	and a helper class to use it.

	A NSF file is a header and a stub program attached to the
	music driver and associated data from a NES rom. It works
	by actually emulating the NES cpu to run the driver code
	and then the NES apu to create the pcm data.
+/
module ff1nsf.nosefart;

extern(C) {
	struct nsf_t;

	alias c_boolean = int;
	int nsf_init();
	// if filename is null it uses source/length instead
	nsf_t* nsf_load(const char* filename, const void* source, int length);
	void nsf_free(nsf_t**);
	int nsf_setchan(nsf_t *nsf, int chan, c_boolean enabled);
	void nsf_frame(nsf_t*);
	int nsf_playtrack(nsf_t *nsf, int track, int sample_rate, int sample_bits, c_boolean stereo);

	void apu_process(void* buffer, int num_samples);
}

/++
	A convenience class for using the nosefart code to play NES music.
+/
class NosefartPlayer {
	private nsf_t* nsf;

	bool playing;

	/++
		Constructs the player and [load]s the given data.
	+/
	this(const(ubyte)[] nsfFileData) {
		static shared(bool) nsfInited;
		synchronized if(!nsfInited) { // intentional global sync
			nsf_init();
			nsfInited = true;
		}

		channelsEnabled = 0xff;

		if(!load(nsfFileData, 0))
			throw new Exception("NSF load fail");

		buffer = new short[](44100 / 60 * 2 /* for stereo */);
	}

	/++
		Changes the currently playing track.
	+/
	void playTrack(int trackNumber) {
		synchronized(this) {
			playTrackUnlocked(trackNumber);
			changed = true;
			playing = true;
		}
	}

	private void playTrackUnlocked(int trackNumber) {
		if(!nsf) return;

		nsf_playtrack(nsf, trackNumber + 1, 44100, 16, true); // im not sure why the 1 is needed, perhaps just 1-based. in fact the fact i needed a <none> indicates maybe it should be +2 but that seems weird. p sure it is just 1-based and ff1 does another subtract for its own purposes (maybe it treats 0 as a no music indicator)

		foreach(ch; 0 .. 6)
			nsf_setchan(nsf, ch, (channelsEnabled & (1 << ch)) ? true : false);
	}

	/++
		Loads a NSF file from data in memory, and optionally starts playing
		the given track. If trackToPlay is -1, it pauses playback.
	+/
	bool load(const(ubyte[]) nsfFileData, int trackToPlay = -1) {
		synchronized(this) {
			if(nsf)
				nsf_free(&nsf);
			nsf = nsf_load(null, nsfFileData.ptr, cast(int) nsfFileData.length);

			// possible to do from a file like this
			//nsf = nsf_load("/home/me/songs/dw3/dq3.nsf", null, 0);

			if(nsf is null)
				return false;

			if(trackToPlay != -1) {
				playing = true;
				playTrackUnlocked(trackToPlay);
			} else
				playing = false;

			changed = true;
		}

		return true;
	}

	/++
		There are 6 channels on the NES, numbers 0-5. This enables playback from each of them.

		The object remembers which channels are enabled/disabled even as you change tracks and load
		new nsf files. You will have to re-enable them yourself.
	+/
	void setChannelEnabled(int channel, bool enabled) {
		channelsEnabled &= ~(1 << channel);
		if(enabled)
			channelsEnabled |= 1 << channel;
		synchronized(this) if(nsf)
			nsf_setchan(nsf, channel, enabled);
	}

	~this() {
		playing = false;
		destroyed = true;
		if(nsf)
			nsf_free(&nsf);
	}

	/++
		Each NES frame triggers some code. This lets you set a delegate so you can
		also be notified when it updates.

		Please note your delegate is run from whatever thread is calling [fillAudioBuffer]
		(presumably, your audio thread) while the NSF object is locked. Calling any other
		method on this object can deadlock and should not be attempted.

		All you should do is maybe increase a counter or send a message to your main thread.
	+/
	void setFrameNotification(void delegate() frameNotification) {
		synchronized(this)
			this.frameNotification = frameNotification;
	}

	private ubyte channelsEnabled;
	private bool destroyed;
	private bool changed;

	private short[] buffer;
	private short[] bufferPos;

	private void delegate() frameNotification;

	/++
		Function to fill a buffer, compatible with [arsd.simpledisplay]'s addChannel method.

		Given the buffer, it fills it and returns true unless this object has been destroyed.

		---
		AudioOutputThread ao = AudioOutputThread("device");
		ao.addChannel(&nsf.fillAudioBuffer);
		---
	+/
	bool fillAudioBuffer(short[] b) {
		if(destroyed)
			return false;

		if(nsf is null || !playing)
			return true;

		short[] bpos = b;

		while(bpos.length) {
			if(changed || bufferPos.length == 0) {
				synchronized(this) {
					changed = false;
					nsf_frame(nsf);
					if(frameNotification)
						frameNotification();
					apu_process(buffer.ptr, cast(int) buffer.length / 2 /* for stereo */);
					bufferPos = buffer;
				}
			}

			if(bpos.length <= bufferPos.length) {
				bpos[] = bufferPos[0 .. bpos.length];
				bufferPos = bufferPos[bpos.length .. $];
				bpos = bpos[$ .. $];
			} else {
				bpos[0 .. bufferPos.length] = bufferPos[];
				bpos = bpos[bufferPos.length .. $];
				bufferPos = bufferPos[$ .. $];
			}
		}

		b[] /= 4; // just to make the volume more reasonable on my computer...

		return true;
	}
}
