/++
	This file has both the actual midi import logic and the import dialog box UI code.
+/
module ff1nsf.midiimport;

import ff1nsf.constants;

import core.time;

import arsd.midi;
import arsd.minigui;

import ff1nsf.main;


/// uses the customPlayerInfo from the midi file track array objects....
void doMidiImport(int songId, int ff1channel, MidiFile f, int channel, int transposeSemitones) {

	import core.time;
	import ff1nsf.ff1rom;

	auto c1 = editableData.songData(songId, ff1channel).clearSongData();

	int currentOctave = -1;
	int currentTempo = -1;

	Duration position;

	Duration[int] activeNotes;

	bool first = true;

	void addDurationMatch(DurationMatch match, bool playing, int octave, int semitone) {
		if(match.tempo != currentTempo) {
			c1 = c1.addFF1Command(FF1MusicCommand(FF1MusicCommand.Type.Tempo, match.tempo));
			currentTempo = match.tempo;

			if(first) {
				c1 = c1.addFF1Command(FF1MusicCommand(FF1MusicCommand.Type.EnvelopeSpeed, 4));
				c1 = c1.addFF1Command(FF1MusicCommand(FF1MusicCommand.Type.EnvelopePattern, 5));
				first = false;
			}
		}

		if(playing && octave != currentOctave) {
			c1 = c1.addFF1Command(FF1MusicCommand(FF1MusicCommand.Type.Octave, cast(ubyte) octave));
			currentOctave = octave;
		}

		c1 = c1.addFF1Command(FF1MusicCommand(playing ? FF1MusicCommand.Type.Play : FF1MusicCommand.Type.Rest, cast(ubyte) semitone, match.duration));
		if(match.remainder != 0xff)
			c1 = c1.addFF1Command(FF1MusicCommand(FF1MusicCommand.Type.Rest, 0, match.remainder));
	}

	void commitNote(int activeNote, Duration activeNotePosition) {
		activeNote += transposeSemitones;

		int octave = activeNote / 12;
		int semitone = activeNote % 12;

		if(octave < 0)
			octave = 0;
		if(octave >= 4)
			octave = 3;

		auto duration = position - activeNotePosition;

		auto match = DurationMatch(editableData, duration, currentTempo);

		addDurationMatch(match, true, octave, semitone);
	}

	Duration restBegan;
	bool resting = true;

	foreach(item; f.playbackStream) {
		position += item.wait;

		// import std.stdio; writeln(item);

		if(item.event.isMeta)
			continue;
		if(item.event.channel != channel)
			continue;
		if(item.track is null || item.track.customPlayerInfo == 0)
			continue;

		if(item.event.event == MIDI_EVENT_NOTE_ON) {
			if(item.event.data2 == 0)
				goto off;

			if(resting) {
				auto restDuration = position - restBegan;

				auto match = DurationMatch(editableData, restDuration, currentTempo);
				addDurationMatch(match, false, 0, 0);
				resting = false;
			}

			// // no polyphony...
			 if(activeNotes.keys.length == 0)
				activeNotes[item.event.data1] = position;
		} else if(item.event.event == MIDI_EVENT_NOTE_OFF) {
			off:
			if(item.event.data1 in activeNotes) {
				commitNote(item.event.data1, activeNotes[item.event.data1]);
				activeNotes.remove(item.event.data1);

				restBegan = position;
				resting = true;
			}
		}
	}
	//Update();
	//ao.unsuspend();
}

class MidiImportWindow : Window {
	this(MidiFile f, int delegate() getCurrentSelectedSong, void delegate() updateSongAfterImport) {
		super("NSF Midi Import", 450, 450);

		this.f = f;

		new TextLabel("Tracks to scan:", TextAlignment.Left, this);

		auto sw = new ScrollableContainerWidget(this);

		foreach(track; f.tracks) {
			track.customPlayerInfo = 1;
			auto cb = new Checkbox(track.name, sw);
			cb.checked = true;
			cb.addEventListener((track) {
				return (ChangeEvent!bool ce) {
					track.customPlayerInfo = ce.value ? 1 : 0;
				};
			}(track));
		}

		int minOctave = 127/12;
		int maxOctave = 0;

		string[][16] instruments;
		foreach(item; f.playbackStream) {
			if(item.event.isMeta) continue;

			if(item.event.event == MIDI_EVENT_PROGRAM_CHANGE) {
				if(item.event.data1 < instrumentNames.length)
					instruments[item.event.channel] ~= instrumentNames[item.event.data1];
			} else if(item.event.event == MIDI_EVENT_NOTE_ON) {
				auto note = item.event.data1;
				auto octave = note / 12;
				if(octave < minOctave)
					minOctave = octave;
				if(octave > maxOctave)
					maxOctave = octave;
			}
		}

		channelPicker = new DropDownSelection(this);
		import std.string;
		import std.conv;
		foreach(i; 0 .. 16)
			channelPicker.addOption("Channel " ~ to!string(i + 1) ~ " (" ~ instruments[i].join("/") ~ ")");
		channelPicker.setSelection(0);

		auto _this = this;
		auto smw = new class ScrollMessageWidget {
			this() { super(_this); }
			override int heightStretchiness() { return 10; }
		};
		smw.addDefaultWheelListeners(12, 12);
		auto mpw = new MidiPreviewWidget(this, smw);

		import std.conv;
		auto octaveRange = new TextLabel(to!string(maxOctave - minOctave), this);

		//auto importOctave = new VerticalSlider(minOctave, maxOctave, 1, this);

		this.addEventListener("change", { mpw.redraw(); });

		auto hl = new HorizontalLayout(32, this);
		(new Button("Play MIDI", hl)).addEventListener("triggered", {
			if(midiOutThread) {
				midiOutThread.loadStream(f.playbackStream);
				midiOutThread.setCallback(delegate bool(const PlayStreamEvent item) {
					if(item.event.isMeta) return false;
					if(item.track is null) return false;
					if(item.track.customPlayerInfo == 0) return false; // track not checked...

					// FIXME: might be dangerous to call getSelection from here. not sure.
					return (item.event.channel == channelPicker.getSelection);
				});
				midiOutThread.play();
			}
		});

		auto makeImporter(int ff1channel) {
			return delegate() {
				auto sid = getCurrentSelectedSong();
				if(sid < 0) {
					messageBox("You need to select a FF1 song to replace");
					return;
				}

				doMidiImport(sid, ff1channel, f, channelPicker.getSelection, -48); // FIXME transpose ui

				updateSongAfterImport();
			};
		}

		auto setLayout = new HorizontalLayout(32, this);
		(new Button("Set Square 1", setLayout)).addEventListener("triggered", makeImporter(0));
		(new Button("Set Square 2", setLayout)).addEventListener("triggered", makeImporter(1));
		(new Button("Set Triangle", setLayout)).addEventListener("triggered", makeImporter(2));

		/+
		auto hl2 = new HorizontalLayout(32, this);
		new Button("Execute Import", hl2);
		(new Button("Cancel", hl2)).addEventListener("triggered", {
			this.close();
		});
		+/

		this.addEventListener(delegate(scope ClosedEvent ce) {
			if(midiOutThread)
				midiOutThread.stop();
		});
	}

	MidiFile f;

	DropDownSelection channelPicker;
}

class MidiPreviewWidget : Widget {
	enum MSECS_PER_PIXEL = 25;
	this(MidiImportWindow miw, ScrollMessageWidget parent) {
		super(parent);
		this.miw = miw;
		this.smw = parent;

		Duration length;
		foreach(item; miw.f.playbackStream) {
			length += item.wait;
		}

		smw.setTotalArea(cast(int) length.total!"msecs" / MSECS_PER_PIXEL, NOTE_HEIGHT * 128);
		smw.setPosition(0, 64 * NOTE_HEIGHT);

		smw.addEventListener((ScrollEvent se) {
			this.redraw();
		});
	}

	ScrollMessageWidget smw;
	MidiImportWindow miw;

	override void registerMovement() {
		super.registerMovement();
		if(smw)
			smw.setViewableArea(width, height);
	}

	override void paint(WidgetPainter painter) {
		painter.fillColor = Color.white;
		painter.drawRectangle(Point(0,0), Size(width, height));

		Duration[128] notesOn;

		painter.fillColor = Color.red;
		painter.outlineColor = Color.black;

		auto channel = miw.channelPicker.getSelection();

		Duration position;
		foreach(item; miw.f.playbackStream) {
			position += item.wait;

			if(item.event.isMeta)
				continue;

			if(item.event.channel != channel)
				continue;

			if(item.track is null || item.track.customPlayerInfo == 0)
				continue;

			if(item.event.event == MIDI_EVENT_NOTE_ON) {
				if(item.event.data2 == 0)
					goto off;
				notesOn[item.event.data1] = position;
			} else if(item.event.event == MIDI_EVENT_NOTE_OFF) {
				off:

				if(notesOn[item.event.data1]) {
					auto note = item.event.data1;
					auto start = notesOn[note];
					auto duration = position - start;
					//import std.stdio; writeln(duration);

					painter.drawRectangle(
						Point(cast(int) start.total!"msecs" / MSECS_PER_PIXEL, (127-note) * NOTE_HEIGHT) - smw.position,
						Size(cast(int) duration.total!"msecs" / MSECS_PER_PIXEL, NOTE_HEIGHT)
					);
					notesOn[item.event.data1] = Duration.init;
				}
			}
		}
	}

	override int heightStretchiness() { return 9; }
}

