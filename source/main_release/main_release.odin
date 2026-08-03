/*
For making a release exe that does not use hot reload.
*/

package main_release

import game ".."
import "../config"

main :: proc() {
	platform_ctx := config.init()
	context = platform_ctx
	platform, g_mem := game.init(platform_ctx)

	context.allocator = g_mem.allocator
	game.g_context = context

	for !game.should_quit(g_mem) {
		game.poll_input(platform, g_mem)
		game.update_and_render(platform, g_mem)
		game.on_frame_end(platform, g_mem)
	}

	game.shutdown(platform, g_mem)

	config.shutdown(platform_ctx)
}

// make game use good GPU on laptops etc

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
