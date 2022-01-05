// duration 5 is i think as close to quarter note as we get....

module ff1nsf.main;

import arsd.simpleaudio;
import arsd.minigui;
import arsd.midi;
import arsd.midiplayer;

import ff1nsf.constants;

import ff1nsf.nosefart;
import ff1nsf.ff1nsfui;
import ff1nsf.ff1rom;
import ff1nsf.midiimport;

MidiOutputThread* midiOutThread;

import core.time;

void main() {
	static import std.file;

	if(!std.file.exists("ff1.nes")) {
		messageBox("You need to put a ff1.nes file (it must be called that, and vanilla rom best but it seems to work ok with rando roms too) right next to the nsf.exe file. Then, try running it again.");
		return;
	}

	auto nsfFileData = new ubyte[](ROM_DATA_LENGTH + NSF_HEADER_LENGTH + stubProgram.length);
	// file magic number
	nsfFileData[0] = 'N';
	nsfFileData[1] = 'E';
	nsfFileData[2] = 'S';
	nsfFileData[3] = 'M';
	nsfFileData[4] = 0x1a;
	// nsf version number
	nsfFileData[5] = 1;
	// number of tracks
	nsfFileData[6] = cast(ubyte) songs.length;
	// starting song; 1-based. doesn't seem to be used by the actual library
	nsfFileData[7] = 1;
	// load, init, and play addresses. load address = asm org. init address = stub program. register A has song number requested. play address = called each frame
	nsfFileData[8 .. 8 + 6] = [0x00, 0x80, 0x00, 0xc0, 0x00, 0xb0];

	// ntsc play speed, tbh im not sure the exact meaning of these numbers
	nsfFileData[0x6e] = 0x1a;
	nsfFileData[0x6f] = 0x41;

	// and now info from the rom...
	auto nsfCoreData = nsfFileData[NSF_HEADER_LENGTH .. $];

	// rest of header can be left all zeroes, they not important to this

	// now time to load the data off the rom
	auto rom = cast(ubyte[]) std.file.read("ff1.nes");

	auto songTablesAndDriverCode = rom[ROM_OFFSET .. ROM_OFFSET + ROM_DATA_LENGTH];

	nsfCoreData[0 .. ROM_DATA_LENGTH] = songTablesAndDriverCode[];

	editableData = FF1Data(nsfCoreData[0 .. ROM_DATA_LENGTH]);

	// and my mini stub program that inits and jumps to the right place for ff1
	nsfCoreData[ROM_DATA_LENGTH .. ROM_DATA_LENGTH + stubProgram.length] = stubProgram[];

	// /////////////// LOADING COMPLETE ///////////////////

	//import std.stdio; writefln("%(%02x %)", noteTable);

	auto window = new MainWindow("NSF Player");
	import arsd.png;
	window.win.icon = readPngFromBytes(cast(immutable(ubyte)[]) import("logo.png"));

	auto nsf = new NosefartPlayer(nsfFileData);

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

	// add: other channels for non-ff1 roms

	auto smw = new ScrollMessageWidget(window);
	auto display = new NsfWidget(smw);

	nsf.setFrameNotification(delegate() {
		display.frame++;
		display.redraw();
	});

	hl.addEventListener((scope ChangeEvent!bool ce) {
		foreach(channel, control; channelControls)
			if(ce.srcElement is control) {
				display.channelsShowing[channel] = ce.value;
				break;
			}

		foreach(channel, control; channelControls)
			if(ce.srcElement is control) {
				nsf.setChannelEnabled(cast(int) channel, ce.value);
				break;
			}
		Update(true);
	});

	auto ao = AudioOutputThread(true);
	ao.suspend();

	auto mo = MidiOutputThread("hw:4");
	midiOutThread = &mo;
	scope(exit) midiOutThread = null;

	void playSong(int index, bool reloadData = false, bool rebuildUi = true) {
		if(reloadData) {
			nsf.load(nsfFileData, index);
		} else {
			nsf.playTrack(index);
		}

		display.resetPlayerState();

		if(!rebuildUi)
			return;

		if(index < 1)
			return;

		auto songIndex = index - 1;

		display.removeAllChildren();

		foreach(channel; 0 .. 3) {
			auto ptr = editableData.songTable[songIndex * 4 + channel];

			auto octave = 0;
			auto tempo = 0;

			auto magic = editableData.rawData[ptr - LOAD_ADDRESS .. $];
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

	struct Menu {
		static string suggestedName = "cool.nes";
		@menu("&File") {
			/+
			void Open() {
			}
			void Save() {

			}
			+/
			@separator
			void Save_ROM_As(FileName!suggestedName filename) {
				auto newRom = rom.dup;
				newRom[ROM_OFFSET .. ROM_OFFSET + ROM_DATA_LENGTH] = editableData.rawData[];
				std.file.write(filename, newRom);
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
			void Envelope_Patterns() {
				auto e = new Window("Envelope Patterns", 70 * 4, 70 * 4);
				new EnvelopeChooser(e);
				e.show();
			}

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

			@accelerator("F5")
			void Restart() {
				auto sid = chooser.getSelection();
				playSong(sid, true);
			}

			@accelerator("F6")
			void Pause() {
				if(ao.suspended)
					Start();
				else
					Stop();
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
		}

		static string lastMidiFile;
		@menu("Track") {
			void Import_From_Midi(FileName!(lastMidiFile, ["Midi files\0*.mid;*.midi;*.rmi"]) file) {

				import arsd.midi;

				auto f = new MidiFile();
				f.loadFromBytes(cast(ubyte[]) std.file.read(file));

				auto midiWindow = new MidiImportWindow(f,
					delegate {
						return chooser.getSelection() - 1;
					},
					delegate {
						Update();
					}
				);

				midiWindow.show();
			}
		}

		private void Update(bool rebuildUi = true) {
			auto sid = chooser.getSelection();
			playSong(sid, true, rebuildUi);
		}
		private void Stop() {
			ao.suspend();
		}

		private void Start() {
			//playSong(chooser.getSelection());
			ao.unsuspend();
		}


		@menu("&Help") {
			void About() {

			}
		}
	}

	Menu menu;

	Update = &menu.Update;

	window.setMenuAndToolbarFromAnnotatedCode(menu);

	//chooser.addEventListener((ChangeEvent!int ce) {
	chooser.addEventListener((scope DropDownSelection.SelectionChangedEvent ce) {
		playSong(ce.intValue);
	});

	ao.addChannel(&nsf.fillAudioBuffer);

	window.loop();
}
