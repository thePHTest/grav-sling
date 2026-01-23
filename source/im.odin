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

	// 2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
	{
		f : f32 = 0.0
		counter : int = 0

		im.Begin("Hello, world!")                          // Create a window called "Hello, world!" and append into it.

		im.Text("This is some useful text.")               // Display some text (you can use a format strings too)
		im.Checkbox("Demo Window", &show_demo_window)      // Edit bools storing our window open/close state
		im.Checkbox("Another Window", &show_another_window)

		im.SliderFloat("float", &f, 0.0, 1.0)            // Edit 1 float using a slider from 0.0f to 1.0f
		im.ColorEdit3("clear color", &clear_color) // Edit 3 floats representing a color

		if im.Button("Button") {                           // Buttons return true when clicked (most widgets return true when edited/activated)
			counter += 1
		}
		im.SameLine()
		im.Text("counter = %d", counter)

		io := im.GetIO()
		im.Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0 / io.Framerate, io.Framerate)
		im.End()
	}

	// 3. Show another simple window.
	if show_another_window {
		im.Begin("Another Window", &show_another_window)   // Pass a pointer to our bool variable (the window will have a closing button that will clear the bool when clicked)
		im.Text("Hello from another window!")
		if im.Button("Close Me") {
			show_another_window = false
		}
		im.End()
	}

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
        sdl.RenderClear(g_sdl_renderer)
        ImGui_ImplSDLRenderer3_RenderDrawData(im.GetDrawData(), g_sdl_renderer)
	}


}


