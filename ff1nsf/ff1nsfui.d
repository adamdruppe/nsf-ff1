module ff1nsf.ff1nsfui;

import ff1nsf.constants;

import ff1nsf.ff1rom;

import arsd.minigui;

import core.time;

class NsfWidget : Widget {
	ScrollMessageWidget smw;
	this(ScrollMessageWidget parent) {
		this.smw = parent;
		super(parent);

		parent.addDefaultWheelListeners(NOTE_HEIGHT);

		smw.addEventListener((scope ScrollEvent se) {
			foreach(child; children) {
				child.x -= smw.position.x - lastScrollX;
				child.y -= smw.position.y - lastScrollY;
			}
			lastScrollX = smw.position.x;
			lastScrollY = smw.position.y;
			redraw();
		});



		this.addEventListener((MouseDownEvent ev) {
			dragging = cast(NsfPieceWidget) ev.target;
			if(dragging is null)
				return;
			if(dragging.command.type != FF1MusicCommand.Type.Play && dragging.command.type != FF1MusicCommand.Type.Rest) {
				dragging = null;
				return;
			}
			this.parentWindow.captureMouse(dragging);
		});

		this.addEventListener((MouseUpEvent ev) {
			this.parentWindow.releaseMouseCapture();
			dragging = null;
		});

		this.addEventListener(delegate(MouseMoveEvent ev) {
			if(dragging is null) return;

			if(ev.clientY < 0) {
				//ev.command = ev.command
				dragging.y -= NOTE_HEIGHT;
				dragging.redraw();

				dragging.command.arg--;

				editableData.rawData[dragging.address - LOAD_ADDRESS .. dragging.address - LOAD_ADDRESS + dragging.command.instructionLength] = dragging.command.toBytes();
				Update(false);
			} else if(ev.clientY > NOTE_HEIGHT) {
				dragging.y += NOTE_HEIGHT;
				dragging.redraw();

				dragging.command.arg++;

				editableData.rawData[dragging.address - LOAD_ADDRESS .. dragging.address - LOAD_ADDRESS + dragging.command.instructionLength] = dragging.command.toBytes();
				Update(false);
			}
		});
	}

	NsfPieceWidget dragging;

	bool[3] channelsShowing = true;

	int lastScrollX;
	int lastScrollY;

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

	int[3] timeline;
	NsfPieceWidget[3] current;
	int[3] currentIndex;
	int[3] durationRemaining;
	int[3] loopsPerformed;

	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		if(children.length == 0 || durationRemaining[0] <= -1)
			return bounds;

		const frame = this.frame;// - 1; // it actually advances this when the buffer is going to the sound card, so we're slightly ahead of reality

		while(lastFrameDrawn < frame) {
			foreach(channel; 0 .. 3) {
				if(current[channel] is null) {
					int thing = -1;
					foreach(child; children) {
						auto i = cast(NsfPieceWidget) child;
						if(i.channel == channel)
							break;
						thing++;
					}
					currentIndex[channel] = thing;
					durationRemaining[channel] = 0;
				}

				while(durationRemaining[channel] == 0) {
					currentIndex[channel]++;
					current[channel] = cast(NsfPieceWidget) children[currentIndex[channel]];
					assert(current[channel] !is null);
					if(current[channel].command.type == FF1MusicCommand.Type.End)
						durationRemaining = -1;
					else if(current[channel].command.type == FF1MusicCommand.Type.Loop) {
						if(current[channel].command.arg && loopsPerformed[channel] == current[channel].command.arg) {
							// do nothing, we just proceed
							durationRemaining[channel] = 0;
							loopsPerformed[channel] = 0;
						} else {
							// otherwise it is infinite or we still have some left
							timeline[channel] = 0;
							if(current[channel].command.arg)
								loopsPerformed[channel]++;
							durationRemaining[channel] = 0;
							currentIndex[channel] = -1;
							foreach(child; children) {
								if(child is current[channel].loopTo)
									break;

								auto i = cast(NsfPieceWidget) child;
								if(i.channel == channel)
									timeline[channel] += (cast(NsfPieceWidget) child).duration;
								currentIndex[channel]++;
							}
						}
					} else {
						durationRemaining[channel] = current[channel].duration;
					}
				}

				timeline[channel]++;
				durationRemaining[channel]--;
			}

			lastFrameDrawn++;
		}

		foreach(channel; 0 .. 3) {
			if(!channelsShowing[channel])
				continue;
			Color c;
			c.components[0 .. 3] = 0;
			c.components[3] = 255;
			c.components[channel] = 255;
			painter.outlineColor = c;
			painter.drawLine(Point(timeline[channel] * FRAME_ZOOM - smw.position.x + channel, 0), Point(timeline[channel] * FRAME_ZOOM - smw.position.x + channel, this.height));
		}
		return bounds;
	}
}

void delegate(bool) Update;

class NsfPieceWidget : Widget {
	this(ushort address, int channel, int octave, int duration, FF1MusicCommand command, NsfWidget parent) {
		this.address = address;
		this.channel = channel;
		this.octave = octave;
		this.command = command;
		this.duration = duration;
		this.parent = parent;
		import std.conv;
		this.statusTip = to!string(command);
		super(parent);

		this.addEventListener((DoubleClickEvent ev) {
			this.command.dialog((FF1MusicCommand cmd) {
				if(cmd.instructionLength == this.command.instructionLength) {
					editableData.rawData[address - LOAD_ADDRESS .. address - LOAD_ADDRESS + cmd.instructionLength] = cmd.toBytes();
					this.command = cmd;

					Update(true);
				} else
					messageBox("The commands have different length and could not be added automatically.");
			});
		});
	}

	NsfWidget parent;

	int octave;
	int channel;
	int duration;
	FF1MusicCommand command;

	ushort address;

	NsfPieceWidget loopTo;

	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {

		if(!parent.channelsShowing[channel])
			return bounds;

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

class EnvelopeChooser : Widget {
	// 64x64 images

	// there's only 16 speeds and here it is:
	// .DB $80,$60,$40,$30,$20,$18,$10,$0C,$08,$06,$04,$03,$02,$01,$00,$00

	// only affects squares; ignored in triangles. but the original sets them anyway... why?
		// just to 8/c on everything unless it is unused.


	this(Widget parent) {
		super(parent);

		//auto scw = new ScrollableContainerWidget(this);
		//auto layout = new InlineBlockLayout(scw);
		foreach(item; 0 .. 16)
			new EnvelopePreview(item, this);//layout);
	}

	override void recomputeChildLayout() {
		int x;
		int y = -70;
		foreach(idx, child; children) {

			x += child.minWidth;
			if(idx % 4 == 0) {
				x = 0;
				y += child.minHeight;
			}

			child.x = x;
			child.y = y;
			child.width = child.minWidth;
			child.height = child.minHeight;

			child.recomputeChildLayout();
		}
	}
}

class EnvelopePreview : Widget {
	override int minWidth() { return 70; }
	override int minHeight() { return 70; }

	int item;
	this(int item, Widget parent) {
		this.item = item;
		super(parent);
	}

	static class Style : Widget.Style {
		override WidgetBackground background() {
			return WidgetBackground(Color.white);
		}

		override Color borderColor() {
			return Color.black;
		}
		override FrameStyle borderStyle() { return FrameStyle.solid; }
	}
	mixin OverrideStyle!Style;

	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		auto table = editableData.envelopePatternTable(item);
		//import std.stdio; writefln("%d %($%02x %)", item, table);

		int prev = table[0];
		int slot;
		foreach(int next; table[1 .. $]) {
			painter.drawLine(bounds.lowerLeft + Point(2 * slot, -prev * 4), bounds.lowerLeft + Point(2 * (slot + 1), -next * 4));
			slot++;
			prev = next;
		}

		return bounds;
	}
}
