package game

import sdl "vendor:sdl3"
import im "deps:odin-imgui"

im_render :: proc() {
	// Start the Dear ImGui frame
	when RENDERER_SDL_GPU {
		ImGui_ImplSDLGPU3_NewFrame()
	} else {
		ImGui_ImplSDLRenderer3_NewFrame()
	}
	ImGui_ImplSDL3_NewFrame()
	im.NewFrame()

	// 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
	if show_demo_window {
		im.ShowDemoWindow(&show_demo_window)
	}

	avatar_im_render(&g_mem.rc)

	// Rendering
	when RENDERER_SDL_GPU {
		im.Render()
		draw_data := im.GetDrawData()
		is_minimized := draw_data.DisplaySize.x <= 0.0 || draw_data.DisplaySize.y <= 0.0

		command_buffer := sdl.AcquireGPUCommandBuffer(g_gpu_device) // Acquire a GPU command buffer

		swapchain_texture : ^sdl.GPUTexture
		if !sdl.WaitAndAcquireGPUSwapchainTexture(command_buffer, g_window, &swapchain_texture, nil, nil) {// Acquire a swapchain texture
			log.error("sdl.WaitAndAcquireGPUSwapchainTexture() failed:", sdl.GetError())
		}

		if swapchain_texture != nil && !is_minimized {
			// This is mandatory: call ImGui_ImplSDLGPU3_PrepareDrawData() to upload the vertex/index buffer!
			ImGui_ImplSDLGPU3_PrepareDrawData(draw_data, command_buffer)

			// Setup and start a render pass
			target_info : sdl.GPUColorTargetInfo
			target_info.texture = swapchain_texture
			target_info.clear_color = sdl.FColor { clear_color.x, clear_color.y, clear_color.z, 1.0 }
			target_info.load_op = .CLEAR
			target_info.store_op = .STORE
			target_info.mip_level = 0
			target_info.layer_or_depth_plane = 0
			target_info.cycle = false
			render_pass := sdl.BeginGPURenderPass(command_buffer, &target_info, 1, nil)

			// Render ImGui
			ImGui_ImplSDLGPU3_RenderDrawData(draw_data, command_buffer, render_pass)

			sdl.EndGPURenderPass(render_pass)
		}

		io := im.GetIO()
		// Update and Render additional Platform Windows
		if .ViewportsEnable in io.ConfigFlags {
			im.UpdatePlatformWindows()
			im.RenderPlatformWindowsDefault()
		}

		// Submit the command buffer
		if !sdl.SubmitGPUCommandBuffer(command_buffer) {
			log.error("sdl.SubmitGPUCommandBuffer() failed:", sdl.GetError())
		}
	} else {
		im.Render()
		io := im.GetIO()
        sdl.SetRenderScale(g_sdl_renderer, io.DisplayFramebufferScale.x, io.DisplayFramebufferScale.y)
        sdl.SetRenderDrawColorFloat(g_sdl_renderer, clear_color.x, clear_color.y, clear_color.z, 1.0)
        //sdl.RenderClear(g_sdl_renderer)
        ImGui_ImplSDLRenderer3_RenderDrawData(im.GetDrawData(), g_sdl_renderer)
	}


}


