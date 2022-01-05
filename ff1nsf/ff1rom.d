/++
	This file has code specific to processing the FF1 NES rom file
	and interpreting its driver commands.
+/
module ff1nsf.ff1rom;

import core.time;

FF1Data editableData;

/++
	This is just a
           STA Music_Track
           JMP AUDIOIN
	stub to play a song, pre-assembled. The nsf thing goes here after setting the song number,
	then it is responsible to go to the original code from the ROM.

	It is used by the nsf thing to get everything started.
+/
immutable(ubyte)[] stubProgram = [0x85, 0x4b, 0x4c, 0x03, 0xb0];

string[] songs = [
	"<none>", // i don't know why it needs this...
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

// offset into the music data...
enum DURATION_TABLE_OFFSET = 0x1d1c;
enum ENVELOPE_TABLE_OFFSET = 0x33c9;

// This is the offset into the rom file for the data we want. It slices this
// out and most everything else is relative to it.
// I just found that offset by looking at the file in a hex editor...
enum ROM_OFFSET = 0x034010;

// This is the address the code is loaded into on the 6502, so any internal
// pointers and loops etc are relative to this.
enum LOAD_ADDRESS = 0x8000;

// i might not actually need all of this but meh, better to take too much than too little.
enum ROM_DATA_LENGTH = 0xC000 - LOAD_ADDRESS;
enum NSF_HEADER_LENGTH = 128;

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

	// it returns a temporary static buffer, you should copy it right out to somewhere else immediately
	ubyte[] toBytes() {
		static ubyte[3] buffer;

		with(Type)
		final switch(type) {
			case Play:
				buffer[0] = cast(ubyte) (arg << 4 | duration);
			break;
			case Rest:
				buffer[0] = 0xc0 | duration;
			break;
			case Loop:
				buffer[0] = 0xd0 | arg;
				buffer[1] = address & 0xff;
				buffer[2] = address >> 8;
			break;
			case Octave:
				buffer[0] = cast(ubyte) (0xd0 | (arg + 8));
			break;
			case EnvelopePattern:
				buffer[0] = 0xe0 | arg;
			break;
			case EnvelopeSpeed:
				buffer[0] = 0xf8;
				buffer[1] = arg;
			break;
			case Tempo:
				buffer[0] = cast(ubyte) (0xf0 | (arg + 9));
			break;
			case End:
				buffer[0] = 0xff;
			break;
		}

		return buffer[0 .. instructionLength];
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

ubyte[] clearSongData(ubyte[] data) {
	data[] = 0xCf; // shortest duration rest
	data[$-1] = 0xff; // end of song marker

	// FIXME: put tempo then envelope speed then pattern at start 

	return data;
}

ubyte[] addFF1Command(ubyte[] data, FF1MusicCommand cmd) {
	if(data.length < cmd.instructionLength + 1)
		return data; // can't modify anymore, need at least an end-of-song marker
	data[0 .. cmd.instructionLength] = cmd.toBytes();
	return data[cmd.instructionLength .. $];
}


struct DurationMatch {
	this(FF1Data data, Duration d, int preferredTempo = -1) {
		const msecs = d.total!"msecs";

		ubyte bestTempo;
		ubyte bestSlot;
		ubyte bestRemainder;
		float bestDifference = float.infinity;

		ubyte bestTempoBt;
		ubyte bestSlotBt;
		ubyte bestRemainderBt;
		float bestDifferenceBt = float.infinity;

		int tempo;
		int slot = -1;
		foreach(idx, frames; data.durationTable) {
			slot++;
			if(slot == 16) {
				slot = 0;
				tempo++;
			}

			auto time = frames * 1000.0 / 60.0;
			auto diff = msecs - time;
			if(diff < 0)
				diff = -diff;

			if(diff < bestDifference) {
				bestTempo = cast(ubyte) idx / 16;
				bestSlot = cast(ubyte) idx % 16;
				bestDifference = diff;
				bestRemainder = 0xff;
			}

			if(tempo == preferredTempo && diff < bestDifferenceBt) {
				bestTempoBt = cast(ubyte) idx / 16;
				bestSlotBt = cast(ubyte) idx % 16;
				bestDifferenceBt = diff;
				bestRemainderBt = 0xff;
			}

			foreach(remainderSlot, remainderFrames; data.durationTable[tempo * 16 .. tempo * 16 + 16]) {
				auto t2 = time + remainderFrames * 1000.0 / 60.0;
				auto d2 = msecs - t2;
				if(d2 < 0)
					d2 = -d2;

				if(d2 < bestDifference) {
					bestTempo = cast(ubyte) idx / 16;
					bestSlot = cast(ubyte) idx % 16;
					bestDifference = d2;
					bestRemainder = cast(ubyte) remainderSlot;
				}

				if(tempo == preferredTempo && d2 < bestDifferenceBt) {
					bestTempoBt = cast(ubyte) idx / 16;
					bestSlotBt = cast(ubyte) idx % 16;
					bestDifferenceBt = d2;
					bestRemainderBt = cast(ubyte) remainderSlot;
				}
			}
		}

		if(bestDifferenceBt < 20) {
			// good enough, use it to save bytes on switching tempos
			this.tempo = bestTempoBt;
			this.duration = bestSlotBt;
			this.remainder = bestRemainderBt;
		} else {
			this.tempo = bestTempo;
			this.duration = bestSlot;
			this.remainder = bestRemainder;
		}
	}

	ubyte tempo;
	ubyte duration;

	ubyte remainder = 0xff;
}

struct FF1Data {
	ubyte[] rawData;

	ushort[] songTable() {
		return cast(ushort[]) rawData[0 .. 4 * 2 * 24];
	}
	ubyte[] durationTable() {
		return rawData[DURATION_TABLE_OFFSET .. DURATION_TABLE_OFFSET + 16 * 6];
	}
	ubyte[] envelopeSpeedTable() {
		enum offset = DURATION_TABLE_OFFSET + 16 * 6; // right after duration table
		return rawData[offset .. offset + 16];
	}
	ubyte[] envelopePatternTable(int slot) {
		slot &= 0x0f;
		enum offset = ENVELOPE_TABLE_OFFSET;

		return rawData[offset + slot * 32 .. offset + slot * 32 + 32];
	}

	ubyte[] songData(int songIndex, int channel) {
		assert(songIndex >= 0 && songIndex < songs.length);
		assert(channel >= 0 && channel < 3);

		auto ptr = songTable[songIndex * 4 + channel];

		auto magic = rawData[ptr - LOAD_ADDRESS .. $];
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

	ubyte[] allSongData() {
		enum SONG_DATA_OFFSET = 4 * 2 * 24; // end of the jump table begins the data table
		return rawData[SONG_DATA_OFFSET .. SONG_DATA_OFFSET + 7262]; // and length i just looked up myself
	}
}

// Note copied from the FF1 Music Driver Disassembly asm file on romhacking.net.
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





