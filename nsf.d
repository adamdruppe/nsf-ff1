/+
	I want a generic nosefart ui replacement

	and i want the ff1 editor
+/

// duration 5 is i think as close to quarter note as we get....

import arsd.simpleaudio;
import arsd.minigui;

enum FRAME_ZOOM = 1;
enum NOTE_HEIGHT = 12;

extern(C) {
	struct nsf_t;

	alias c_boolean = int;
	int nsf_init();
	// if filename is null it uses source/length instead
	nsf_t* nsf_load(const char* filename, void* source, int length);
	void nsf_free(nsf_t**);
	int nsf_setchan(nsf_t *nsf, int chan, c_boolean enabled);
	void nsf_frame(nsf_t*);
	int nsf_playtrack(nsf_t *nsf, int track, int sample_rate, int sample_bits, c_boolean stereo);

	void apu_process(void* buffer, int num_samples);
}

string[] songs = [
	"<none>",
	"Prelude",
	"Prologue",
	"Ending",
	"Overworld",
	"Ship",
	"Airship",
	"Town",
	"Castle",
	"Volcano / Earth",
	"Matoya",
	"Marsh / Mirage",
	"Sea",
	"Sky",
	"Tofr",
	"Shop",
	"Battle",
	"Menu",
	"Perished",
	"Victory",
	"Key Item",
	"Prelude (same song, repeated index)",
	"Saved",
	"Heal pot",
	"Treasure",
];

class NsfWidget : Widget {
	ScrollMessageWidget smw;
	this(ScrollMessageWidget parent) {
		this.smw = parent;
		super(parent);

		smw.addEventListener((scope ScrollEvent se) {
			queueRecomputeChildLayout();
		});
	}

	static class Style : Widget.Style {
		override WidgetBackground background() {
			return WidgetBackground(Color.white);
		}
	}
	mixin OverrideStyle!Style;

	override void recomputeChildLayout() {
		int[3] frame = 0;
		ubyte[128] stack;
		ubyte lastNote;
		int maxY;

		int max = this.height;
		enum MAX_NOTE_Y = NOTE_HEIGHT * 12 /* 12 semitones */ * 4 /* 4 octaves */ - NOTE_HEIGHT + NOTE_HEIGHT * 3 /* space for the stack */;
		if(max < MAX_NOTE_Y)
			max = MAX_NOTE_Y;

		int maxStack(Widget child) {
			if(child.x < 0)
				return 0;
			auto rangeMin = child.x / 24;
			if(rangeMin > stack.length)
				rangeMin = stack.length;
			auto rangeMax = (child.x + child.width + 23) / 24;
			if(rangeMax > stack.length)
				rangeMax = stack.length;

			auto maxStack = 0;
			foreach(ref item; stack[rangeMin .. rangeMax]) {
				if(item > maxStack)
					maxStack = item;
				item += 1;
			}

			return maxStack * NOTE_HEIGHT;
		}

		foreach(child; children) {
			auto i = cast(NsfPieceWidget) child;

			child.x = frame[i.channel] * FRAME_ZOOM;
			child.height = NOTE_HEIGHT;

			with(FF1MusicCommand.Type)
			final switch(i.command.type) {
				case Play:
					lastNote = cast(ubyte) (i.command.arg + i.octave * 12);
					goto case;
				case Rest:
					child.y = max - NOTE_HEIGHT * lastNote - NOTE_HEIGHT;
					child.width = i.duration * FRAME_ZOOM;
				break;
				case Loop:
					if(i.loopTo is null)
						goto case End;
					auto want = child.x;
					child.x = i.loopTo.x;
					child.width = want - child.x;
					child.y = maxStack(child);
				break;
				case Octave:
				case EnvelopePattern:
				case EnvelopeSpeed:
				case Tempo:
				case End:
					child.width = 24;
					child.y = maxStack(child);
			}

			frame[i.channel] += i.duration;

			auto m = child.y + child.height;
			if(m > maxY)
				maxY = m;

			child.x -= smw.position.x;
			child.y -= smw.position.y;

			child.recomputeChildLayout();
		}

		smw.setTotalArea(frame[0], maxY);
		smw.setViewableArea(this.width, this.height);
	}

	void resetPlayerState() {
		lastFrameDrawn = 0;
		frame = 0;
		timeline = 0;
		current = null;
		durationRemaining = 0;
		loopsPerformed = 0;
	}

	int frame;
	int lastFrameDrawn;
	int timeline;
	NsfPieceWidget current;
	int currentIndex;
	int durationRemaining;
	int loopsPerformed;
	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		if(children.length == 0 || durationRemaining <= -1)
			return bounds;

		const frame = this.frame;// - 1; // it actually advances this when the buffer is going to the sound card, so we're slightly ahead of reality

		while(lastFrameDrawn < frame) {
			if(current is null) {
				currentIndex = -1;
				durationRemaining = 0;
			}

			while(durationRemaining == 0) {
				currentIndex++;
				current = cast(NsfPieceWidget) children[currentIndex];
				assert(current !is null);
				if(current.command.type == FF1MusicCommand.Type.End)
					durationRemaining = -1;
				else if(current.command.type == FF1MusicCommand.Type.Loop) {
					if(current.command.arg && loopsPerformed == current.command.arg) {
						// do nothing, we just proceed
						durationRemaining = 0;
						loopsPerformed = 0;
					} else {
						// otherwise it is infinite or we still have some left
						timeline = 0;
						if(current.command.arg)
							loopsPerformed++;
						durationRemaining = 0;
						currentIndex = -1;
						foreach(child; children) {
							if(child is current.loopTo)
								break;
							timeline += (cast(NsfPieceWidget) child).duration;
							currentIndex++;
						}
					}
				} else {
					durationRemaining = current.duration;
				}
			}

			timeline++;
			durationRemaining--;

			lastFrameDrawn++;
		}

		painter.drawLine(Point(timeline * FRAME_ZOOM - smw.position.x, 0), Point(timeline * FRAME_ZOOM - smw.position.x, this.height));
		return bounds;
	}
}

class NsfPieceWidget : Widget {
	this(ushort address, int channel, int octave, int duration, FF1MusicCommand command, Widget parent) {
		this.address = address;
		this.channel = channel;
		this.octave = octave;
		this.command = command;
		this.duration = duration;
		import std.conv;
		this.statusTip = to!string(command);
		super(parent);

		this.addEventListener((DoubleClickEvent ev) {
			dialog((FF1MusicCommand cmd) {
				this.command = cmd;
			});
		});
	}

	int octave;
	int channel;
	int duration;
	FF1MusicCommand command;

	ushort address;

	NsfPieceWidget loopTo;

	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		auto channelColor = channel == 0 ? Color.red : channel == 1 ? Color.green : Color.blue;

		with(FF1MusicCommand.Type)
		final switch(command.type) {
			case Play:
				painter.fillColor = channelColor;
				painter.outlineColor = Color.black;
			break;
			case Rest:
				painter.outlineColor = channelColor;
				painter.fillColor = Color.transparent;
			break;
			case Octave:
			case EnvelopePattern:
			case EnvelopeSpeed:
			case Tempo:
			case End:
			case Loop:
				painter.outlineColor = channelColor;
				painter.fillColor = Color.transparent;
			break;
		}
		painter.drawRectangle(bounds);

		string text;
		TextAlignment alignment = TextAlignment.Left;

		import std.format;
		with(FF1MusicCommand.Type)
		final switch(command.type) {
			case Play:
			case Rest:
			break;
			case Loop:
				text = format("%d", command.arg);
				alignment = TextAlignment.Right;
			break;
			case Octave:
				text = format("O-%X", command.arg);
			break;
			case EnvelopePattern:
				text = format("P-%X", command.arg);
			break;
			case EnvelopeSpeed:
				text = format("E-%X", command.arg);
			break;
			case Tempo:
				text = format("T-%X", command.arg);
			break;
			case End:
				text = "END";
			break;
		}

		if(text.length) {
			painter.outlineColor = Color.black;
			painter.drawText(bounds.upperLeft + Point(3, 0), text, bounds.lowerRight - Point(3, 0), alignment);
		}

		return bounds;
	}
	//override void erase(WidgetPainter painter) {}

	class Style : Widget.Style {
		override WidgetBackground background() {
			return WidgetBackground(Color.transparent);
		}
	}
	mixin OverrideStyle!Style;
}

// offset into the music data...
enum DURATION_TABLE_OFFSET = 0x1d1c;

struct FF1Data {
	ubyte[] rawData;

	ushort[] songTable() {
		return cast(ushort[]) rawData[0 .. 4 * 2 * 24];
	}
	ubyte[] durationTable() {
		return rawData[DURATION_TABLE_OFFSET .. DURATION_TABLE_OFFSET + 16 * 6];
	}

	ubyte[] songData(int songIndex, int channel) {
		assert(songIndex >= 0 && songIndex < songs.length);
		assert(channel >= 0 && channel < 3);

		auto ptr = songTable[songIndex * 4 + channel];

		auto magic = rawData[ptr - 0x8000 .. $];
		auto s = magic;

		int index;
		while(magic.length) {
			auto cmd = parseCommand(magic);
			index += cmd.instructionLength();
			if(cmd.isEndOfSong)
				break;
		}

		return s[0 .. index];
	}
}
FF1Data editableData;

void main() {
	static import std.file;

	// I just found that offset by looking at the file in a hex editor...
	enum ROM_OFFSET = 0x034010;
	// i might not actually need all of this but meh.
	enum ROM_DATA_LENGTH = 0xC000 - 0x8000;
	enum NSF_HEADER_LENGTH = 128;

	auto nsfFileData = new ubyte[](ROM_DATA_LENGTH + NSF_HEADER_LENGTH + stubProgram.length);
	nsfFileData[0] = 'N';
	nsfFileData[1] = 'E';
	nsfFileData[2] = 'S';
	nsfFileData[3] = 'M';
	nsfFileData[4] = 0x1a;
	nsfFileData[5] = 1; // nsf version number
	nsfFileData[6] = cast(ubyte) songs.length;
	nsfFileData[7] = 1; // starting song
	nsfFileData[8 .. 8 + 6] = [0x00, 0x80, 0x00, 0xc0, 0x00, 0xb0]; // load, init, play addresses

	// ntsc play speed
	nsfFileData[0x6e] = 0x1a;
	nsfFileData[0x6f] = 0x41;

	auto nsfCoreData = nsfFileData[NSF_HEADER_LENGTH .. $];

	// rest of header can be left all zeroes, they not important to this

	// now time to load the data off the rom
	auto rom = cast(ubyte[]) std.file.read("ff1.nes");

	auto songTablesAndDriverCode = rom[ROM_OFFSET .. ROM_OFFSET + ROM_DATA_LENGTH];

	nsfCoreData[0 .. ROM_DATA_LENGTH] = songTablesAndDriverCode[];

	editableData = FF1Data(nsfCoreData[0 .. ROM_DATA_LENGTH]);

	nsfCoreData[ROM_DATA_LENGTH .. ROM_DATA_LENGTH + stubProgram.length] = stubProgram[];

	// /////////////// LOADING COMPLETE ///////////////////

	//import std.stdio; writefln("%(%02x %)", noteTable);

	auto window = new MainWindow("NSF Player");
	import arsd.png;
	window.win.icon = readPngFromBytes(cast(immutable(ubyte)[]) import("logo.png"));

	nsf_init();
	auto nsf = nsf_load(null, nsfFileData.ptr, cast(int) nsfFileData.length);
	//auto nsf = nsf_load("/home/me/songs/dw3/dq3.nsf", null, 0);
	scope(exit) nsf_free(&nsf);

	assert(nsf);

	bool playingNsf;

	short[] buffer = new short[](44100 / 60 * 2 /* for stereo */);
	short[] bufferPos;

	bool changed;

	auto chooser = new DropDownSelection(window);
	foreach(song; songs)
		chooser.addOption(song);

	auto hl = new HorizontalLayout(window);
	auto sq1 = new Checkbox("Square 1 (red)", hl);
	auto sq2 = new Checkbox("Square 2 (green)", hl);
	auto tri = new Checkbox("Triangle (blue)", hl);
	auto channelControls = [sq1, sq2, tri];
	foreach(c; channelControls)
		c.checked = true;
	hl.addEventListener((scope ChangeEvent!bool ce) {
		if(!playingNsf)
			return;
		foreach(channel, control; channelControls)
			if(ce.srcElement is control) {
				synchronized {
					nsf_setchan(nsf, cast(int) channel, ce.value);
				}
				break;
			}
	});

	// add: other channels for non-ff1 roms

	auto smw = new ScrollMessageWidget(window);
	auto display = new NsfWidget(smw);

	void playSong(int index, bool reloadData = false) {
		synchronized {
			if(reloadData) {
				nsf_free(&nsf);
				nsf = nsf_load(null, nsfFileData.ptr, cast(int) nsfFileData.length);
			}

			nsf_playtrack(nsf, index + 1 /* track number */, 44100, 16, true);
			// it re-enables all channels when you change tracks, so this will resync
			foreach(channel, control; channelControls)
				nsf_setchan(nsf, cast(int) channel, control.checked);
			changed = true;
			playingNsf = true;
			display.resetPlayerState();
		}

		if(index < 1)
			return;

		auto songIndex = index - 1;

		display.removeAllChildren();

		foreach(channel; 0 .. 3) {
			auto ptr = editableData.songTable[songIndex * 4 + channel];

			auto octave = 0;
			auto tempo = 0;

			auto magic = editableData.rawData[ptr - 0x8000 .. $];
			ushort currentAddress = ptr;

			auto channelStart = display.children.length;

			while(magic.length) {
				auto cmd = parseCommand(magic);

				int dur;

				if(cmd.type == FF1MusicCommand.Type.Play || cmd.type == FF1MusicCommand.Type.Rest)
					dur = editableData.durationTable[16 * tempo + cmd.duration];

				if(cmd.type == FF1MusicCommand.Type.Octave)
					octave = cmd.arg;
				if(cmd.type == FF1MusicCommand.Type.Tempo)
					tempo = cmd.arg;

				auto w = new NsfPieceWidget(currentAddress, channel, octave, dur, cmd, display);
				currentAddress += cmd.instructionLength();

				if(cmd.type == FF1MusicCommand.Type.Loop) {
					auto addr = ptr;
					foreach(child; display.children[channelStart .. $]) {
						auto i = cast(NsfPieceWidget) child;
						if(i.address == cmd.address) {
							w.loopTo = i;
						}
					}
				}

				if(cmd.isEndOfSong)
					break;
			}
		}

	}

	auto ao = AudioOutputThread(true);

	struct Menu {
		@menu("&File") {
			void Open() {
			}
			void Save() {

			}
			void Save_As() {
				auto newRom = rom.dup;
				newRom[ROM_OFFSET .. ROM_OFFSET + ROM_DATA_LENGTH] = editableData.rawData[];
				std.file.write("ff1-newmusic.nes", newRom);

			}
			@separator
			void Exit() {
				window.close();
			}
		}

		int speed = 1;
		int pattern = 1;
		int tempo = 0;

		@menu("&Edit") {
			@accelerator("F1")
			void Speed_Down() {
				auto sid = chooser.getSelection()-1;
				auto sd = editableData.songData(sid, 0);
				sd[2] = cast(ubyte) --speed; // speed
				Update();
			}

			@accelerator("F2")
			void Speed_Up() {
				auto sid = chooser.getSelection()-1;
				auto sd = editableData.songData(sid, 0);
				sd[2] = cast(ubyte) ++speed; // speed
				Update();
			}

			@accelerator("F3")
			void Prev_Pattern() {
				pattern--;
				auto sid = chooser.getSelection()-1;
				auto sd = editableData.songData(sid, 0);
				sd[3] &= 0xf0;
				sd[3] |= pattern & 0xf;

				Update();
			}

			@accelerator("F4")
			void Next_Pattern() {
				pattern++;
				auto sid = chooser.getSelection()-1;
				auto sd = editableData.songData(sid, 0);
				sd[3] &= 0xf0;
				sd[3] |= pattern & 0xf;

				Update();
			}

			@accelerator("F7")
			void Tempo_Down() {
				if(tempo == 0)
					return;
				auto sid = chooser.getSelection()-1;
				auto sd = editableData.songData(sid, 0);
				tempo--;
				sd[0] &= 0xf0;
				sd[0] |= (tempo & 0xf) + 9;

				Update();
			}

			@accelerator("F8")
			void Tempo_Up() {
				if(tempo == 5)
					return;
				auto sid = chooser.getSelection()-1;
				auto sd = editableData.songData(sid, 0);
				tempo++;
				sd[0] &= 0xf0;
				sd[0] |= (tempo & 0xf) + 9;

				Update();
			}


			@accelerator("F5")
			void Update() {
				auto sid = chooser.getSelection();
				playSong(sid, true);
			}

			void Stop() {
				playingNsf = false;
				ao.pause();
			}

			void Start() {
				playSong(chooser.getSelection());
				ao.unpause();
			}
		}

		@menu("&Help") {
			void About() {

			}
		}
	}

	Menu menu;

	window.setMenuAndToolbarFromAnnotatedCode(menu);

	//chooser.addEventListener((ChangeEvent!int ce) {
	chooser.addEventListener((scope DropDownSelection.SelectionChangedEvent ce) {
		playSong(ce.intValue);
	});
	ao.addChannel((short[] b) {
		if(!playingNsf)
			return true;

		short[] bpos = b;

		while(bpos.length) {
			if(changed || bufferPos.length == 0) {
				synchronized {
					changed = false;
					nsf_frame(nsf);
					display.frame++;
					display.redraw();
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
	});

	window.loop();
}

immutable string[] noteNames = [ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" ];
string durationString(ubyte duration) {
	return ((duration < 10) ? ("" ~ cast(char)(duration + '0')) : ("1" ~ cast(char)(duration + '0' - 10)));
}

struct FF1MusicCommand {
	enum Type {
		Play,
		Rest,
		Loop,
		Octave,
		EnvelopePattern,
		EnvelopeSpeed,
		Tempo,
		End
	}

	Type type;
	ubyte arg; // the note for play, number of loops, or other argument for most things
	ubyte duration; // for note and rest

	ushort address; // for loops

	int instructionLength() {
		if(type == Type.EnvelopeSpeed)
			return 2;
		else if(type == Type.Loop)
			return 3;
		return 1;
	}

	bool isEndOfSong() {
		return type == Type.End || (type == Type.Loop && arg == 0);
	}

	version(none)
	string toString() const {
		// FIXME
	}
}

FF1MusicCommand parseCommand(ref ubyte[] arr) {
	// songs can end on 0xff or 0xd0

	auto b = arr[0];
	arr = arr[1 .. $];

	if(b <= 0xbf) {
		return FF1MusicCommand(FF1MusicCommand.Type.Play, b >> 4, b & 0xf);
	} else if(b <= 0xcf) {
		return FF1MusicCommand(FF1MusicCommand.Type.Rest, 0, b & 0xf);
	} else if(b <= 0xd7) {
		ubyte iterations = b & 0xf;

		ushort addr = arr[0] | (arr[1] << 8);
		arr = arr[2 .. $];

		return FF1MusicCommand(FF1MusicCommand.Type.Loop, iterations, 0, addr);
	} else if(b <= 0xdf) {
		// octaves 4+ are broken!
		ubyte octave = cast(ubyte) ((b & 0x0f) - 8);
		return FF1MusicCommand(FF1MusicCommand.Type.Octave, octave);
	} else if(b <= 0xef) {
		ubyte pattern = b & 0x0f;
		return FF1MusicCommand(FF1MusicCommand.Type.EnvelopePattern, pattern);
	} else if(b == 0xf8) {
		ubyte speed = arr[0];
		arr = arr[1 .. $];

		return FF1MusicCommand(FF1MusicCommand.Type.EnvelopeSpeed, speed);
	} else if(b >= 0xf9 && b <= 0xfe) {
		ubyte tempo = cast(ubyte)((b & 0xf) - 9);
		return FF1MusicCommand(FF1MusicCommand.Type.Tempo, tempo);
	} else if(b == 0xff) {
		return FF1MusicCommand(FF1MusicCommand.Type.End);
	} else throw new Exception("broken ff1 song data");
}


/+
;------------------------------------------------------------------------
; Sequence Data
;------------------------------------------------------------------------
; This is the sequence data that you can edit. Below is a quick and dirty
; reference chart to use.
;------------------------------------------------------------------------
; 00 - BF = Play a note. High order nibble specifies which note to play.
; 0x = C, 1x = C#, 2x = D, etc.
; Low order nibble specifies length of note.
;
; C0 - CF = Rest. Low order nibble specifies the length of rest. Only the
; Triangle channel truly rests. The other notes are sustained.
;
; D0 = Infinite loop. A two byte pointer follows the "D0" byte indicating
; where to loop back to.
;
; D1 - D7 = Loop count. Low order nibble specifies number of times to loop.
; You cannot nest loops in loops, however you can nest a loop in an infinite
; loop.
;
; D8 - DB = Octave select. Low order nibble selects the octave. Four octaves
; to choose from.
;
; DC - DF = Unused. Bugged octave select.
;
; E0 - EF = Envelope pattern select. Low order nibble selects which envelope
; pattern to use.
;
; F0 - F7 = Unused.
;
; F8 = One byte follows this byte. The byte that follows; the low order nibble
; selects the envelope speed.
;
; F9 - FE = Tempo select. Low order nibble selects which tempo to use.
;
; FF = End of songs marker. Stops all music playback.
+/






/++
	This is just a
           STA Music_Track
           JMP AUDIOIN
	stub to play a song, pre-assembled. The nsf thing goes here after setting the song number,
	then it is responsible to go to the original code from the ROM.
+/
immutable(ubyte)[] stubProgram = [0x85, 0x4b, 0x4c, 0x03, 0xb0];
