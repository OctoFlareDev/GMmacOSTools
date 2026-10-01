#include "../GMmacOSTools/MouseInputQueue.hpp"
#include <cassert>
#include <iostream>

using namespace gm_input;

static MouseEvent down(unsigned button = 1, double x = .25, double y = .5) {
    return {MouseKind::down, button, x, y, 1};
}
static MouseEvent up(unsigned button = 1, double x = .25, double y = .5) {
    return {MouseKind::up, button, x, y, 1};
}

int main() {
    {
        MouseInputQueue q;
        q.push(down()); q.push(up()); q.push(down()); q.push(up());
        for (int click = 0; click < 2; ++click) {
            auto f = q.step(1.1);
            assert(f.pressed == 1 && f.held == 1 && !f.released);
            f = q.step(1.2);
            assert(f.released == 1 && !f.held && !f.pressed);
        }
        auto f = q.step(1.3);
        assert(!f.pressed && !f.released && !f.held);
    }
    {
        MouseInputQueue q;
        q.push(down(1, .1, .2));
        q.push({MouseKind::move, 1, .4, .5, 1});
        q.push({MouseKind::move, 1, .8, .9, 1});
        q.push(up(1, .8, .9));
        auto f = q.step(1);
        assert(f.x == .1 && f.y == .2 && f.pressed == 1);
        f = q.step(1);
        assert(f.x == .8 && f.y == .9 && f.held == 1 && !f.released);
        f = q.step(1);
        assert(f.x == .8 && f.y == .9 && f.released == 1);
    }
    {
        MouseInputQueue q;
        q.push(down()); q.push(up(1, 1.2, -.1));
        q.step(1);
        auto f = q.step(1);
        assert(f.released == 1 && f.x == 1.2 && f.y == -.1);
    }
    {
        MouseInputQueue q;
        q.push(down(2)); q.push(down(4)); q.push(up(2)); q.push(up(4));
        assert(q.step(1).held == 2);
        assert(q.step(1).held == 6);
        auto f = q.step(1);
        assert(f.held == 4 && f.released == 2);
        assert(q.step(1).released == 4);
    }
    {
        MouseInputQueue q;
        q.push(down()); q.step(1); q.push(up());
        q.cancel(); // Losing focus or opening a native menu cancels, not clicks.
        auto f = q.step(1);
        assert(f.cancelled && !f.pressed && !f.released && !f.held);
        q.push(up());
        assert(!q.step(1).released); // Orphan release after reactivation.
        q.push(down()); q.push(up());
        assert(q.step(1).pressed == 1);
        assert(q.step(1).released == 1);
    }
    {
        MouseInputQueue q;
        q.push(down()); q.push(down()); q.push(up()); q.push(up());
        assert(q.step(1).pressed == 1);
        assert(q.step(1).released == 1);
        assert(!q.step(1).released);
    }
    {
        MouseInputQueue q;
        q.push(down()); q.step(1);
        q.push(up()); q.push(down(2));
        q.clearButtons(1); // Clearing left does not erase another button.
        auto f = q.step(1);
        assert(f.pressed == 2 && f.held == 2 && !f.released);
        q.clearButtons(7);
        assert(!q.step(1).held);
    }
    {
        MouseInputQueue q;
        for (unsigned i = 0; i <= MouseInputQueue::capacity; ++i) q.push(i % 2 ? up() : down());
        auto f = q.step(1);
        assert(f.cancelled && !f.pressed && !f.released && !f.held);
    }
    {
        MouseInputQueue q;
        for (unsigned i = 0; i < 10000; ++i) q.push({MouseKind::move, 0, i / 10000., .5, 1});
        auto f = q.step(1);
        assert(!f.cancelled && f.valid && f.x == .9999);
    }
    {
        MouseInputQueue q;
        q.push(down()); q.push(up());
        auto f = q.step(4); // Do not replay stale clicks after a blocked dialog.
        assert(f.cancelled && !f.pressed && !f.released && !f.held);
        q.push(down()); q.step(1);
        assert(q.step(100).held == 1); // A live long press is not a stale queue.
    }
    std::cout << "Mouse input: 10 scenarios passed\n";
}
