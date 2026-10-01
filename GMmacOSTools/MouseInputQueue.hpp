#pragma once

#include <algorithm>
#include <cstdint>
#include <deque>

namespace gm_input {

enum class MouseKind { move, down, up };

struct MouseEvent {
    MouseKind kind;
    unsigned button; // GML button bits: left=1, right=2, middle=4.
    double x, y;     // Content coordinates, normalized to the window size.
    double time;     // Monotonic time when the event was received.
};

struct MouseFrame {
    double x = 0, y = 0;
    unsigned held = 0, pressed = 0, released = 0;
    bool valid = false, cancelled = false;
};

// Adapt an ordered event stream to GameMaker's Step/Draw input lifetime.
// Opposite edges must not collapse into a single sampled button state.
class MouseInputQueue {
public:
    static constexpr unsigned capacity = 512;
    static constexpr double maxPendingAge = 2.0;

    void push(MouseEvent event) {
        if (event.kind == MouseKind::move && !events.empty() &&
            events.back().kind == MouseKind::move) {
            events.back() = event;
            return;
        }
        if (events.size() >= capacity) {
            cancel(); // Never replay a partial click after an overflow.
            return;
        }
        events.push_back(event);
    }

    void cancel() {
        events.clear();
        state.held = state.pressed = state.released = 0;
        cancelled = true;
    }

    void clearButtons(unsigned mask) {
        state.held &= ~mask;
        state.pressed &= ~mask;
        state.released &= ~mask;
        events.erase(std::remove_if(events.begin(), events.end(), [mask](const MouseEvent &event) {
            return event.kind != MouseKind::move && (event.button & mask);
        }), events.end());
    }

    MouseFrame step(double now) {
        state.pressed = state.released = 0;
        if (!events.empty() && now - events.front().time > maxPendingAge) cancel();
        state.cancelled = cancelled;
        cancelled = false;

        bool movedWhileHeld = false;
        while (!events.empty()) {
            const auto event = events.front();
            // Let the UI apply the final drag position before it sees release.
            if (movedWhileHeld && event.kind != MouseKind::move) break;
            events.pop_front();
            state.x = event.x;
            state.y = event.y;
            state.valid = true;

            if (event.kind == MouseKind::move) {
                movedWhileHeld = state.held != 0;
                continue;
            }
            if (event.kind == MouseKind::down && !(state.held & event.button)) {
                state.held |= event.button;
                state.pressed = event.button;
                break;
            }
            if (event.kind == MouseKind::up && (state.held & event.button)) {
                state.held &= ~event.button;
                state.released = event.button;
                break;
            }
            // Ignore duplicate downs and releases without an observed press.
        }
        return state;
    }

private:
    std::deque<MouseEvent> events;
    MouseFrame state;
    bool cancelled = false;
};

} // namespace gm_input
