package game

import im "deps:odin-imgui"
import "core:c/libc"
import "core:fmt"
import "core:mem"
import "base:runtime"
import sdl "vendor:sdl3"

IMTEXTUREID_INVALID :: 0
IMDRAWCALLBACK_RESETRENDERSTATE :: -8

// From .h file:
// dear imgui: Renderer Backend for SDL_GPU
// This needs to be used along with the SDL3 Platform Backend

// Implemented features:
//  [X] Renderer: User texture binding. Use 'SDL_GPUTexture*' as texture identifier. Read the FAQ about ImTextureID/ImTextureRef! **IMPORTANT** Before 2025/08/08, ImTextureID was a reference to a SDL_GPUTextureSamplerBinding struct.
//  [X] Renderer: Large meshes support (64k+ vertices) even with 16-bit indices (ImGuiBackendFlags_RendererHasVtxOffset).
//  [X] Renderer: Texture updates support for dynamic font atlas (ImGuiBackendFlags_RendererHasTextures).
//  [X] Renderer: Multi-viewport support (multiple windows). Enable with 'io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable'.

// The aim of imgui_impl_sdlgpu3.h/.cpp is to be usable in your engine without any modification.
// IF YOU FEEL YOU NEED TO MAKE ANY CHANGE TO THIS CODE, please share them and your feedback at https://github.com/ocornut/imgui/

// You can use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// Important note to the reader who wish to integrate imgui_impl_sdlgpu3.cpp/.h in their own engine/app.
// - Unlike other backends, the user must call the function ImGui_ImplSDLGPU_PrepareDrawData BEFORE issuing a SDL_GPURenderPass containing ImGui_ImplSDLGPU_RenderDrawData.
//   Calling the function is MANDATORY, otherwise the ImGui will not upload neither the vertex nor the index buffer for the GPU. See imgui_impl_sdlgpu3.cpp for more info.

//#pragma once
//#include "imgui.h"      // IMGUI_IMPL_API
//#ifndef IMGUI_DISABLE
//#include <SDL3/SDL_gpu.h>

// Initialization data, for ImGui_ImplSDLGPU_Init()
// - Remember to set ColorTargetFormat to the correct format. If you're rendering to the swapchain, call SDL_GetGPUSwapchainTextureFormat() to query the right value
ImGui_ImplSDLGPU3_InitInfo :: struct {
	device : ^sdl.GPUDevice,
    color_target_format : sdl.GPUTextureFormat,
    msaa_samples : sdl.GPUSampleCount,
    swapchain_composition : sdl.GPUSwapchainComposition,     // Only used in multi-viewports mode.
    present_mode : sdl.GPUPresentMode,            // Only used in multi-viewports mode.
}

// [BETA] Selected render state data shared with callbacks.
// This is temporarily stored in GetPlatformIO().Renderer_RenderState during the ImGui_ImplSDLGPU3_RenderDrawData() call.
// (Please open an issue if you feel you need access to more data)
ImGui_ImplSDLGPU3_RenderState :: struct {
	device : ^sdl.GPUDevice,
    sampler_default : ^sdl.GPUSampler,     // Default sampler (bilinear filtering)
    sampler_current : ^sdl.GPUSampler,     // Current sampler (may be changed by callback)
}

// dear imgui: Renderer Backend for SDL_GPU
// This needs to be used along with the SDL3 Platform Backend

// Implemented features:
//  [X] Renderer: User texture binding. Use 'SDL_GPUTexture*' as texture identifier. Read the FAQ about ImTextureID/ImTextureRef! **IMPORTANT** Before 2025/08/08, ImTextureID was a reference to a SDL_GPUTextureSamplerBinding struct.
//  [X] Renderer: Large meshes support (64k+ vertices) even with 16-bit indices (ImGuiBackendFlags_RendererHasVtxOffset).
//  [X] Renderer: Texture updates support for dynamic font atlas (ImGuiBackendFlags_RendererHasTextures).
//  [X] Renderer: Multi-viewport support (multiple windows). Enable with 'io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable'.

// The aim of imgui_impl_sdlgpu3.h/.cpp is to be usable in your engine without any modification.
// IF YOU FEEL YOU NEED TO MAKE ANY CHANGE TO THIS CODE, please share them and your feedback at https://github.com/ocornut/imgui/

// You can use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// Important note to the reader who wish to integrate imgui_impl_sdlgpu3.cpp/.h in their own engine/app.
// - Unlike other backends, the user must call the function ImGui_ImplSDLGPU3_PrepareDrawData() BEFORE issuing a SDL_GPURenderPass containing ImGui_ImplSDLGPU3_RenderDrawData.
//   Calling the function is MANDATORY, otherwise the ImGui will not upload neither the vertex nor the index buffer for the GPU. See imgui_impl_sdlgpu3.cpp for more info.

// CHANGELOG
//  2025-XX-XX: Platform: Added support for multiple windows via the ImGuiPlatformIO interface.
//  2025-11-26: macOS version can use MSL shaders in order to support macOS 10.14+ (vs Metallib shaders requiring macOS 14+). Requires calling SDL_CreateGPUDevice() with SDL_GPU_SHADERFORMAT_MSL.
//  2025-09-18: Call platform_io.ClearRendererHandlers() on shutdown.
//  2025-08-20: Added ImGui_ImplSDLGPU3_InitInfo::SwapchainComposition and ImGui_ImplSDLGPU3_InitInfo::PresentMode to configure how secondary viewports are created.
//  2025-08-08: *BREAKING* Changed ImTextureID type from SDL_GPUTextureSamplerBinding* to SDL_GPUTexture*, which is more natural and easier for user to manage. If you need to change the current sampler, you can access the ImGui_ImplSDLGPU3_RenderState struct. (#8866, #8163, #7998, #7988)
//  2025-08-08: Expose SamplerDefault and SamplerCurrent in ImGui_ImplSDLGPU3_RenderState. Allow callback to change sampler.
//  2025-06-25: Mapping transfer buffer for texture update use cycle=true. Fixes artifacts e.g. on Metal backend.
//  2025-06-11: Added support for ImGuiBackendFlags_RendererHasTextures, for dynamic font atlas. Removed ImGui_ImplSDLGPU3_CreateFontsTexture() and ImGui_ImplSDLGPU3_DestroyFontsTexture().
//  2025-04-28: Added support for special ImDrawCallback_ResetRenderState callback to reset render state.
//  2025-03-30: Made ImGui_ImplSDLGPU3_PrepareDrawData() reuse GPU Transfer Buffers which were unusually slow to recreate every frame. Much faster now.
//  2025-03-21: Fixed typo in function name Imgui_ImplSDLGPU3_PrepareDrawData() -> ImGui_ImplSDLGPU3_PrepareDrawData().
//  2025-01-16: Renamed ImGui_ImplSDLGPU3_InitInfo::GpuDevice to Device.
//  2025-01-09: SDL_GPU: Added the SDL_GPU3 backend.

//#include "imgui.h"
//#ifndef IMGUI_DISABLE
//#include "imgui_impl_sdlgpu3.h"
//#include "imgui_impl_sdlgpu3_shaders.h"

// SDL_GPU Data

// Reusable buffers used for rendering 1 current in-flight frame, for ImGui_ImplSDLGPU3_RenderDrawData()
ImGui_ImplSDLGPU3_FrameData :: struct {
	vertex_buffer : ^sdl.GPUBuffer,
    vertex_transfer_buffer : ^sdl.GPUTransferBuffer,
    vertex_buffer_size : u32,
    index_buffer : ^sdl.GPUBuffer,
    index_transfer_buffer : ^sdl.GPUTransferBuffer,
    index_buffer_size : u32,
}

ImGui_ImplSDLGPU3_Data :: struct {
	init_info : ImGui_ImplSDLGPU3_InitInfo,

    // Graphics pipeline & shaders
    vertex_shader : ^sdl.GPUShader,
	fragment_shader :^sdl.GPUShader,
	pipeline : ^sdl.GPUGraphicsPipeline,
	tex_sampler_linear : ^sdl.GPUSampler,
	tex_transfer_buffer :^sdl.GPUTransferBuffer,
	tex_transfer_buffer_size : u32,

    // Frame data for main window
    main_window_frame_date : ImGui_ImplSDLGPU3_FrameData,
}

//-----------------------------------------------------------------------------
// FUNCTIONS
//-----------------------------------------------------------------------------

// Backend data stored in io.BackendRendererUserData to allow support for multiple Dear ImGui contexts
// It is STRONGLY preferred that you use docking branch with multi-viewports (== single Dear ImGui context + multiple windows) instead of multiple Dear ImGui contexts.
// FIXME: multi-context support has never been tested.
ImGui_ImplSDLGPU3_GetBackendData :: proc "c" () -> ^ImGui_ImplSDLGPU3_Data {
    return im.GetCurrentContext() != nil ? cast(^ImGui_ImplSDLGPU3_Data)im.GetIO().BackendRendererUserData : nil
}

ImGui_ImplSDLGPU3_SetupRenderState :: proc(draw_data : ^im.DrawData, render_state : ^ImGui_ImplSDLGPU3_RenderState, pipeline :
^sdl.GPUGraphicsPipeline, command_buffer : ^sdl.GPUCommandBuffer, render_pass : ^sdl.GPURenderPass, fd :
^ImGui_ImplSDLGPU3_FrameData, fb_width : u32, fb_height : u32) {
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    render_state.sampler_current = bd.tex_sampler_linear

    // Bind graphics pipeline
    sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

    // Bind Vertex And Index Buffers
    if draw_data.TotalVtxCount > 0 {
		vertex_buffer_binding : sdl.GPUBufferBinding
        vertex_buffer_binding.buffer = fd.vertex_buffer
        vertex_buffer_binding.offset = 0
        index_buffer_binding : sdl.GPUBufferBinding
        index_buffer_binding.buffer = fd.index_buffer
        index_buffer_binding.offset = 0
        sdl.BindGPUVertexBuffers(render_pass, 0, &vertex_buffer_binding, 1)
        sdl.BindGPUIndexBuffer(render_pass, index_buffer_binding, size_of(im.DrawIdx) == 2 ? ._16BIT : ._32BIT)
    }

    // Setup viewport
	viewport : sdl.GPUViewport
    viewport.x = 0
    viewport.y = 0
    viewport.w = cast(f32)fb_width
    viewport.h = cast(f32)fb_height
    viewport.min_depth = 0.0
    viewport.max_depth = 1.0
    sdl.SetGPUViewport(render_pass, viewport)

    // Setup scale and translation
    // Our visible imgui space lies from draw_data.DisplayPps (top left) to draw_data.DisplayPos+data_data.DisplaySize (bottom right). DisplayPos is (0,0) for single viewport apps.
    ubo : struct { scale : [2]f32, translation : [2]f32 }
    ubo.scale[0] = 2.0 / draw_data.DisplaySize.x
    ubo.scale[1] = 2.0 / draw_data.DisplaySize.y
    ubo.translation[0] = -1.0 - draw_data.DisplayPos.x * ubo.scale[0]
    ubo.translation[1] = -1.0 - draw_data.DisplayPos.y * ubo.scale[1]
    sdl.PushGPUVertexUniformData(command_buffer, 0, &ubo, size_of(ubo))
}

CreateOrResizeBuffers :: proc "c" (buffer : ^^sdl.GPUBuffer, transfer_buffer : ^^sdl.GPUTransferBuffer, old_size : ^u32, new_size :
u32, usage : sdl.GPUBufferUsageFlags) {
	context = runtime.default_context()
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    v := &bd.init_info

    // FIXME-OPT: Not optimal, but this is fairly rarely called.
    if !sdl.WaitForGPUIdle(v.device) {
		// TODO: log
		fmt.println("sdl.WairForGpuIdle() failed:", sdl.GetError())
	}
    sdl.ReleaseGPUBuffer(v.device, buffer^)
    sdl.ReleaseGPUTransferBuffer(v.device, transfer_buffer^)

    buffer_info : sdl.GPUBufferCreateInfo
    buffer_info.usage = usage
    buffer_info.size = new_size
    buffer_info.props = 0
    buffer^ = sdl.CreateGPUBuffer(v.device, buffer_info)
    old_size^ = new_size
    assert(buffer^ != nil, "Failed to create GPU Buffer, call sdl.GetError() for more information")

    transfer_buffer_info : sdl.GPUTransferBufferCreateInfo
    transfer_buffer_info.usage = .UPLOAD
    transfer_buffer_info.size = new_size
    transfer_buffer^ = sdl.CreateGPUTransferBuffer(v.device, transfer_buffer_info)
    assert(transfer_buffer^ != nil, "Failed to create GPU Transfer Buffer, call sdl.GetError() for more information")
}

// sdl.GPU doesn't allow copy passes to occur while a render or compute pass is bound!
// The only way to allow a user to supply their own RenderPass (to render to a texture instead of the window for example),
// is to split the upload part of ImGui_ImplSDLGPU3_RenderDrawData() to another function that needs to be called by the user before rendering.
ImGui_ImplSDLGPU3_PrepareDrawData :: proc "c" (draw_data : ^im.DrawData, command_buffer : ^sdl.GPUCommandBuffer) {
    // Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
	fb_width := (int)(draw_data.DisplaySize.x * draw_data.FramebufferScale.x)
	fb_height := (int)(draw_data.DisplaySize.y * draw_data.FramebufferScale.y)
    if fb_width <= 0 || fb_height <= 0 || draw_data.TotalVtxCount <= 0 {
        return
	}

    // Catch up with texture updates. Most of the times, the list will have 1 element with an OK status, aka nothing to do.
    // (This almost always points to ImGui::GetPlatformIO().Textures[] but is part of ImDrawData to allow overriding or disabling texture updates).
    if draw_data.Textures != nil {
        for tex_idx in 0..<draw_data.Textures.Size {
			tex := (cast([^]^im.TextureData)draw_data.Textures.Data)[tex_idx]
            if tex.Status != .OK {
                ImGui_ImplSDLGPU3_UpdateTexture(tex)
			}
		}
	}

	bd := ImGui_ImplSDLGPU3_GetBackendData()
    v := &bd.init_info
    fd := &bd.main_window_frame_date

    vertex_size : u32 = u32(draw_data.TotalVtxCount * size_of(im.DrawVert))
    index_size  : u32 = u32(draw_data.TotalIdxCount * size_of(im.DrawIdx))
    if fd.vertex_buffer == nil || fd.vertex_buffer_size < vertex_size {
        CreateOrResizeBuffers(&fd.vertex_buffer, &fd.vertex_transfer_buffer, &fd.vertex_buffer_size, vertex_size, {.VERTEX})
	}
    if fd.index_buffer == nil || fd.index_buffer_size < index_size {
        CreateOrResizeBuffers(&fd.index_buffer, &fd.index_transfer_buffer, &fd.index_buffer_size, index_size, {.INDEX})
	}

	vtx_dst := cast([^]im.DrawVert)sdl.MapGPUTransferBuffer(v.device, fd.vertex_transfer_buffer, true)
    idx_dst := cast([^]im.DrawIdx)sdl.MapGPUTransferBuffer(v.device, fd.index_transfer_buffer, true)
    for draw_list_idx in 0..<draw_data.CmdLists.Size {
		draw_list := (cast([^]^im.DrawList)draw_data.CmdLists.Data)[draw_list_idx]
        mem.copy(vtx_dst, draw_list.VtxBuffer.Data, int(draw_list.VtxBuffer.Size * size_of(im.DrawVert)))
        mem.copy(idx_dst, draw_list.IdxBuffer.Data, int(draw_list.IdxBuffer.Size * size_of(im.DrawIdx)))
        vtx_dst = &vtx_dst[draw_list.VtxBuffer.Size]
        idx_dst = &idx_dst[draw_list.IdxBuffer.Size]
    }
    sdl.UnmapGPUTransferBuffer(v.device, fd.vertex_transfer_buffer)
    sdl.UnmapGPUTransferBuffer(v.device, fd.index_transfer_buffer)

    vertex_buffer_location : sdl.GPUTransferBufferLocation
    vertex_buffer_location.offset = 0
    vertex_buffer_location.transfer_buffer = fd.vertex_transfer_buffer
    index_buffer_location : sdl.GPUTransferBufferLocation
    index_buffer_location.offset = 0
    index_buffer_location.transfer_buffer = fd.index_transfer_buffer

    vertex_buffer_region : sdl.GPUBufferRegion
    vertex_buffer_region.buffer = fd.vertex_buffer
    vertex_buffer_region.offset = 0
    vertex_buffer_region.size = vertex_size

    index_buffer_region : sdl.GPUBufferRegion
    index_buffer_region.buffer = fd.index_buffer
    index_buffer_region.offset = 0
    index_buffer_region.size = index_size

    copy_pass := sdl.BeginGPUCopyPass(command_buffer)
    sdl.UploadToGPUBuffer(copy_pass, vertex_buffer_location, vertex_buffer_region, true)
    sdl.UploadToGPUBuffer(copy_pass, index_buffer_location, index_buffer_region, true)
    sdl.EndGPUCopyPass(copy_pass)
}

ImGui_ImplSDLGPU3_RenderDrawData :: proc(draw_data : ^im.DrawData, command_buffer : ^sdl.GPUCommandBuffer, render_pass :
^sdl.GPURenderPass, pipeline : ^sdl.GPUGraphicsPipeline = nil) {
    // Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
	fb_width := cast(i32)(draw_data.DisplaySize.x * draw_data.FramebufferScale.x)
    fb_height := cast(i32)(draw_data.DisplaySize.y * draw_data.FramebufferScale.y)
    if fb_width <= 0 || fb_height <= 0 {
        return
	}

	bd := ImGui_ImplSDLGPU3_GetBackendData()
    fd := &bd.main_window_frame_date

	pipeline := pipeline
    if pipeline == nil {
        pipeline = bd.pipeline
	}

    // Will project scissor/clipping rectangles into framebuffer space
	clip_off := draw_data.DisplayPos         // (0,0) unless using multi-viewports
    clip_scale := draw_data.FramebufferScale // (1,1) unless using retina display which are often (2,2)

    // Setup render state structure (for callbacks and custom texture bindings)
    platform_io := im.GetPlatformIO()
    render_state : ImGui_ImplSDLGPU3_RenderState
    render_state.device = bd.init_info.device
    render_state.sampler_default = bd.tex_sampler_linear
    render_state.sampler_current = bd.tex_sampler_linear
    platform_io.Renderer_RenderState = &render_state

    ImGui_ImplSDLGPU3_SetupRenderState(draw_data, &render_state, pipeline, command_buffer, render_pass, fd, u32(fb_width), u32(fb_height))

    // Render command lists
    // (Because we merged all buffers into a single one, we maintain our own offset into them)
    global_vtx_offset := 0
    global_idx_offset := 0
    for draw_list_idx in 0..<draw_data.CmdLists.Size {
		draw_list := (cast([^]^im.DrawList)draw_data.CmdLists.Data)[draw_list_idx]
        for cmd_i : i32 = 0; cmd_i < draw_list.CmdBuffer.Size; cmd_i += 1 {
			pcmd := &(cast([^]im.DrawCmd)draw_list.CmdBuffer.Data)[cmd_i]
            if pcmd.UserCallback != nil {
                // User callback, registered via ImDrawList::AddCallback()
                // (ImDrawCallback_ResetRenderState is a special callback value used by the user to request the renderer to reset render state.)
				// TODO: Is this the correct hacky check here?
				// if pcmd.UserCallback == ImDrawCallback_ResetRenderState
                if cast(int)cast(uintptr)cast(rawptr)pcmd.UserCallback == IMDRAWCALLBACK_RESETRENDERSTATE {
                    ImGui_ImplSDLGPU3_SetupRenderState(draw_data, &render_state, pipeline, command_buffer, render_pass, fd, u32(fb_width), u32(fb_height))
				} else {
                    pcmd.UserCallback(draw_list, pcmd)
				}
            } else {
                // Project scissor/clipping rectangles into framebuffer space
				clip_min := im.Vec2{(pcmd.ClipRect.x - clip_off.x) * clip_scale.x, (pcmd.ClipRect.y - clip_off.y) * clip_scale.y}
				clip_max := im.Vec2{(pcmd.ClipRect.z - clip_off.x) * clip_scale.x, (pcmd.ClipRect.w - clip_off.y) * clip_scale.y}

                // Clamp to viewport as sdl.SetGPUScissor() won't accept values that are off bounds
                if clip_min.x < 0.0 { clip_min.x = 0.0 }
                if clip_min.y < 0.0 { clip_min.y = 0.0 }
                if clip_max.x > f32(fb_width) { clip_max.x = cast(f32)fb_width }
                if clip_max.y > f32(fb_height) { clip_max.y = cast(f32)fb_height }
                if clip_max.x <= clip_min.x || clip_max.y <= clip_min.y {
                    continue
				}

                // Apply scissor/clipping rectangle
				scissor_rect : sdl.Rect
                scissor_rect.x = cast(i32)clip_min.x
                scissor_rect.y = cast(i32)clip_min.y
                scissor_rect.w = cast(i32)(clip_max.x - clip_min.x)
                scissor_rect.h = cast(i32)(clip_max.y - clip_min.y)
                sdl.SetGPUScissor(render_pass, scissor_rect)

                // Bind DescriptorSet with font or user texture
                texture_sampler_binding : sdl.GPUTextureSamplerBinding
                texture_sampler_binding.texture = cast(^sdl.GPUTexture)cast(uintptr)im.DrawCmd_GetTexID(pcmd)
                texture_sampler_binding.sampler = render_state.sampler_current
                sdl.BindGPUFragmentSamplers(render_pass, 0, &texture_sampler_binding, 1)

                // Draw
                // **IF YOU GET A CRASH HERE** In 1.92.2 on 2025/08/08 we have changed ImTextureID to store 'sdl.GPUTexture*'
				// instead of storing 'sdl.GPUTextureSamplerBinding'.
                // Any code loading custom texture using this backend needs to be updated.
                sdl.DrawGPUIndexedPrimitives(render_pass, pcmd.ElemCount, 1, pcmd.IdxOffset + u32(global_idx_offset), i32(pcmd.VtxOffset) + i32(global_vtx_offset), 0)
            }
        }
        global_idx_offset += int(draw_list.IdxBuffer.Size)
        global_vtx_offset += int(draw_list.VtxBuffer.Size)
    }

    // Note: at this point both sdl.SetGPUViewport() and sdl.SetGPUScissor() have been called.
    // Our last values will leak into user/application rendering if you forgot to call sdl.SetGPUViewport() and sdl.SetGPUScissor() yourself to explicitly set that state
    // In theory we should aim to backup/restore those values but I am not sure this is possible.
    // We perform a call to sdl.SetGPUScissor() to set back a full viewport which is likely to fix things for 99% users but technically this is not perfect. (See github #4644)
	scissor_rect := sdl.Rect{ 0, 0, fb_width, fb_height }
    sdl.SetGPUScissor(render_pass, scissor_rect)
}

ImGui_ImplSDLGPU3_DestroyTexture :: proc(tex : ^im.TextureData) {
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    if raw_tex := cast(^sdl.GPUTexture)cast(uintptr)im.TextureData_GetTexID(tex); raw_tex != nil {
        sdl.ReleaseGPUTexture(bd.init_info.device, raw_tex)
	}

    // Clear identifiers and mark as destroyed (in order to allow e.g. calling InvalidateDeviceObjects while running)
    im.TextureData_SetTexID(tex, IMTEXTUREID_INVALID)
    im.TextureData_SetStatus(tex, .Destroyed)
}

ImGui_ImplSDLGPU3_UpdateTexture :: proc "c" (tex : ^im.TextureData) {
	context = runtime.default_context()
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    v := &bd.init_info

    if tex.Status == .WantCreate {
        // Create and upload new texture to graphics system
        //IMGUI_DEBUG_LOG("UpdateTexture #%03d: WantCreate %dx%d\n", tex.UniqueID, tex.Width, tex.Height)
        assert(tex.TexID == IMTEXTUREID_INVALID && tex.BackendUserData == nil)
        assert(tex.Format == .RGBA32)

        // Create texture
		texture_info : sdl.GPUTextureCreateInfo
        texture_info.type = .D2
        texture_info.format = .R8G8B8A8_UNORM
        texture_info.usage = {.SAMPLER}
        texture_info.width = u32(tex.Width)
        texture_info.height = u32(tex.Height)
        texture_info.layer_count_or_depth = 1
        texture_info.num_levels = 1
        texture_info.sample_count = ._1

        raw_tex := sdl.CreateGPUTexture(v.device, texture_info)
        assert(raw_tex != nil, "Failed to create texture, call sdl.GetError() for more info")

        // Store identifiers
        im.TextureData_SetTexID(tex, cast(im.TextureID)cast(uintptr)raw_tex)
    }

    if tex.Status == .WantCreate || tex.Status == .WantUpdates {
		raw_tex := cast(^sdl.GPUTexture)cast(uintptr)im.TextureData_GetTexID(tex)
        assert(tex.Format == .RGBA32)

        // Update full texture or selected blocks. We only ever write to textures regions which have never been used before!
        // This backend choose to use tex.UpdateRect but you can use tex.Updates[] to upload individual regions.
        // We could use the smaller rect on _WantCreate but using the full rect allows us to clear the texture.
        upload_x : i32 = (tex.Status == .WantCreate) ? 0 : i32(tex.UpdateRect.x)
        upload_y : i32 = (tex.Status == .WantCreate) ? 0 : i32(tex.UpdateRect.y)
        upload_w : i32 = (tex.Status == .WantCreate) ? tex.Width : i32(tex.UpdateRect.w)
        upload_h : i32 = (tex.Status == .WantCreate) ? tex.Height : i32(tex.UpdateRect.h)
        upload_pitch : u32 = u32(upload_w * tex.BytesPerPixel)
        upload_size : u32 = u32(upload_w * upload_h * tex.BytesPerPixel)

        // Create transfer buffer
        if bd.tex_transfer_buffer_size < upload_size {
            sdl.ReleaseGPUTransferBuffer(v.device, bd.tex_transfer_buffer)
            transfer_buffer_info : sdl.GPUTransferBufferCreateInfo
            transfer_buffer_info.usage = .UPLOAD
            transfer_buffer_info.size = upload_size + 1024
            bd.tex_transfer_buffer_size = upload_size + 1024
            bd.tex_transfer_buffer = sdl.CreateGPUTransferBuffer(v.device, transfer_buffer_info)
            assert(bd.tex_transfer_buffer != nil, "Failed to create transfer buffer, call sdl.GetError() for more information")
        }

        // Copy to transfer buffer
        {
			texture_ptr := sdl.MapGPUTransferBuffer(v.device, bd.tex_transfer_buffer, true)
            for y : i32 = 0; y < upload_h; y += 1 {
                mem.copy(cast(rawptr)(cast(uintptr)texture_ptr + uintptr(u32(y) * upload_pitch)), im.TextureData_GetPixelsAt(tex, i32(upload_x),
				upload_y + i32(y)), int(upload_pitch))
			}
            sdl.UnmapGPUTransferBuffer(v.device, bd.tex_transfer_buffer)
        }

		transfer_info : sdl.GPUTextureTransferInfo
        transfer_info.offset = 0
        transfer_info.transfer_buffer = bd.tex_transfer_buffer

        texture_region : sdl.GPUTextureRegion
        texture_region.texture = raw_tex
        texture_region.x = cast(u32)upload_x
        texture_region.y = cast(u32)upload_y
        texture_region.w = cast(u32)upload_w
        texture_region.h = cast(u32)upload_h
        texture_region.d = 1

        // Upload
        {
			cmd := sdl.AcquireGPUCommandBuffer(v.device)
            copy_pass := sdl.BeginGPUCopyPass(cmd)
            sdl.UploadToGPUTexture(copy_pass, transfer_info, texture_region, false)
            sdl.EndGPUCopyPass(copy_pass)
            if !sdl.SubmitGPUCommandBuffer(cmd) {
				// TODO: log
				fmt.println("sdl.SubmitGPUCommandBuffer() failed:", sdl.GetError())
			}
        }

        im.TextureData_SetStatus(tex, .OK)
    }
    if (tex.Status == .WantDestroy && tex.UnusedFrames > 0) {
        ImGui_ImplSDLGPU3_DestroyTexture(tex)
	}
}

ImGui_ImplSDLGPU3_CreateShaders :: proc() {
    // Create the shader modules
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    v := &bd.init_info

    driver := sdl.GetGPUDeviceDriver(v.device)

    vertex_shader_info : sdl.GPUShaderCreateInfo
    vertex_shader_info.entrypoint = "main"
    vertex_shader_info.stage = .VERTEX
    vertex_shader_info.num_uniform_buffers  = 1
    vertex_shader_info.num_storage_buffers = 0
    vertex_shader_info.num_storage_textures = 0
    vertex_shader_info.num_samplers = 0

    fragment_shader_info : sdl.GPUShaderCreateInfo
    fragment_shader_info.entrypoint = "main"
    fragment_shader_info.stage = .FRAGMENT
    fragment_shader_info.num_samplers = 1
    fragment_shader_info.num_storage_buffers  = 0
    fragment_shader_info.num_storage_textures = 0
    fragment_shader_info.num_uniform_buffers  = 0

    if libc.strcmp(driver, "vulkan") == 0 {
        vertex_shader_info.format = {.SPIRV}
        vertex_shader_info.code = &spirv_vertex[0]
        vertex_shader_info.code_size = size_of(spirv_vertex)
        fragment_shader_info.format = {.SPIRV}
        fragment_shader_info.code = &spirv_fragment[0]
        fragment_shader_info.code_size = size_of(spirv_fragment)
    } else if libc.strcmp(driver, "direct3d12") == 0 {
        vertex_shader_info.format = {.DXBC}
        vertex_shader_info.code = &dxbc_vertex[0]
        vertex_shader_info.code_size = size_of(dxbc_vertex)
        fragment_shader_info.format = {.DXBC}
        fragment_shader_info.code = &dxbc_fragment[0]
        fragment_shader_info.code_size = size_of(dxbc_fragment)
    } else {
when ODIN_OS == .Darwin {
	supported_formats := sdl.GetGPUShaderFormats(v.device)
        if .METALLIB in supported_formats {
            // Using metallib blobs (macOS 14+, iOS)
            vertex_shader_info.entrypoint = "main0"
            vertex_shader_info.format = .METALLIB
            vertex_shader_info.code = metallib_vertex
            vertex_shader_info.code_size = size_of(metallib_vertex)
            fragment_shader_info.entrypoint = "main0"
            fragment_shader_info.format = s.METALLIB
            fragment_shader_info.code = metallib_fragment
            fragment_shader_info.code_size = size_of(metallib_fragment)
        } else if .MSL in supported_formats {
            // macOS: using MSL source
            vertex_shader_info.entrypoint = "main0"
            vertex_shader_info.format = .MSL
            vertex_shader_info.code = msl_vertex
            vertex_shader_info.code_size = size_of(msl_vertex)
            fragment_shader_info.entrypoint = "main0"
            fragment_shader_info.format = .MSL
            fragment_shader_info.code = msl_fragment
            fragment_shader_info.code_size = size_of(msl_fragment)
        }
}
    }

    bd.vertex_shader = sdl.CreateGPUShader(v.device, vertex_shader_info)
    bd.fragment_shader = sdl.CreateGPUShader(v.device, fragment_shader_info)
    assert(bd.vertex_shader != nil, "Failed to create vertex shader, call sdl.GetError() for more information")
    assert(bd.fragment_shader != nil, "Failed to create fragment shader, call sdl.GetError() for more information")
}

ImGui_ImplSDLGPU3_CreateGraphicsPipeline :: proc() {
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    v := &bd.init_info
    ImGui_ImplSDLGPU3_CreateShaders()

    vertex_buffer_desc : [1]sdl.GPUVertexBufferDescription
    vertex_buffer_desc[0].slot = 0
    vertex_buffer_desc[0].input_rate = .VERTEX
    vertex_buffer_desc[0].instance_step_rate = 0
    vertex_buffer_desc[0].pitch = size_of(im.DrawVert)

    vertex_attributes : [3]sdl.GPUVertexAttribute
    vertex_attributes[0].buffer_slot = 0
    vertex_attributes[0].format = .FLOAT2
    vertex_attributes[0].location = 0
    vertex_attributes[0].offset = u32(offset_of(im.DrawVert,pos))

    vertex_attributes[1].buffer_slot = 0
    vertex_attributes[1].format = .FLOAT2
    vertex_attributes[1].location = 1
    vertex_attributes[1].offset = u32(offset_of(im.DrawVert, uv))

    vertex_attributes[2].buffer_slot = 0
    vertex_attributes[2].format = .UBYTE4_NORM
    vertex_attributes[2].location = 2
    vertex_attributes[2].offset = u32(offset_of(im.DrawVert, col))

    vertex_input_state : sdl.GPUVertexInputState
    vertex_input_state.num_vertex_attributes = 3
    vertex_input_state.vertex_attributes = &vertex_attributes[0]
    vertex_input_state.num_vertex_buffers = 1
    vertex_input_state.vertex_buffer_descriptions = &vertex_buffer_desc[0]

    rasterizer_state : sdl.GPURasterizerState
    rasterizer_state.fill_mode = .FILL
    rasterizer_state.cull_mode = .NONE
    rasterizer_state.front_face = .COUNTER_CLOCKWISE
    rasterizer_state.enable_depth_bias = false
    rasterizer_state.enable_depth_clip = false

    multisample_state : sdl.GPUMultisampleState
    multisample_state.sample_count = v.msaa_samples
    multisample_state.enable_mask = false

    depth_stencil_state : sdl.GPUDepthStencilState
    depth_stencil_state.enable_depth_test = false
    depth_stencil_state.enable_depth_write = false
    depth_stencil_state.enable_stencil_test = false

    blend_state : sdl.GPUColorTargetBlendState
    blend_state.enable_blend = true
    blend_state.src_color_blendfactor = .SRC_ALPHA
    blend_state.dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA
    blend_state.color_blend_op = .ADD
    blend_state.src_alpha_blendfactor = .ONE
    blend_state.dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA
    blend_state.alpha_blend_op = .ADD
    blend_state.color_write_mask = {.R, .G, .B, .A}

	color_target_desc : [1]sdl.GPUColorTargetDescription
    color_target_desc[0].format = v.color_target_format
    color_target_desc[0].blend_state = blend_state

    target_info : sdl.GPUGraphicsPipelineTargetInfo
    target_info.num_color_targets = 1
    target_info.color_target_descriptions = &color_target_desc[0]
    target_info.has_depth_stencil_target = false

    pipeline_info : sdl.GPUGraphicsPipelineCreateInfo
    pipeline_info.vertex_shader = bd.vertex_shader
    pipeline_info.fragment_shader = bd.fragment_shader
    pipeline_info.vertex_input_state = vertex_input_state
    pipeline_info.primitive_type = .TRIANGLELIST
    pipeline_info.rasterizer_state = rasterizer_state
    pipeline_info.multisample_state = multisample_state
    pipeline_info.depth_stencil_state = depth_stencil_state
    pipeline_info.target_info = target_info

    bd.pipeline = sdl.CreateGPUGraphicsPipeline(v.device, pipeline_info)
    assert(bd.pipeline != nil, "Failed to create graphics pipeline, call sdl.GetError() for more information")
}

ImGui_ImplSDLGPU3_CreateDeviceObjects :: proc() {
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    v := &bd.init_info

    ImGui_ImplSDLGPU3_DestroyDeviceObjects()

    if bd.tex_sampler_linear == nil {
        // Bilinear sampling is required by default. Set 'io.Fonts.Flags |= ImFontAtlasFlags_NoBakedLines' or 'style.AntiAliasedLinesUseTex = false' to allow point/nearest sampling.
		sampler_info : sdl.GPUSamplerCreateInfo
        sampler_info.min_filter = .LINEAR
        sampler_info.mag_filter = .LINEAR
        sampler_info.mipmap_mode = .LINEAR
        sampler_info.address_mode_u = .CLAMP_TO_EDGE
        sampler_info.address_mode_v = .CLAMP_TO_EDGE
        sampler_info.address_mode_w = .CLAMP_TO_EDGE
        sampler_info.mip_lod_bias = 0.0
        sampler_info.min_lod = -1000.0
        sampler_info.max_lod = 1000.0
        sampler_info.enable_anisotropy = false
        sampler_info.max_anisotropy = 1.0
        sampler_info.enable_compare = false

        bd.tex_sampler_linear = sdl.CreateGPUSampler(v.device, sampler_info)
        assert(bd.tex_sampler_linear != nil, "Failed to create sampler, call sdl.GetError() for more information")
    }

    ImGui_ImplSDLGPU3_CreateGraphicsPipeline()
}

ImGui_ImplSDLGPU3_DestroyFrameData :: proc() {
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    v := &bd.init_info

    fd := &bd.main_window_frame_date
    sdl.ReleaseGPUBuffer(v.device, fd.vertex_buffer)
    sdl.ReleaseGPUBuffer(v.device, fd.index_buffer)
    sdl.ReleaseGPUTransferBuffer(v.device, fd.vertex_transfer_buffer)
    sdl.ReleaseGPUTransferBuffer(v.device, fd.index_transfer_buffer)
    fd.vertex_buffer = nil
    fd.index_buffer = nil
    fd.vertex_transfer_buffer = nil
    fd.index_transfer_buffer = nil
    fd.vertex_buffer_size = 0
    fd.index_buffer_size = 0
}

ImGui_ImplSDLGPU3_DestroyDeviceObjects :: proc() {
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    v := &bd.init_info

    ImGui_ImplSDLGPU3_DestroyFrameData()

    // Destroy all textures
	platform_io := im.GetPlatformIO()
    for tex_idx in 0..<platform_io.Textures.Size {
		tex := (cast([^]^im.TextureData)platform_io.Textures.Data)[tex_idx]
        if tex.RefCount == 1 {
            ImGui_ImplSDLGPU3_DestroyTexture(tex)
		}
	}
    if bd.tex_transfer_buffer != nil {
		sdl.ReleaseGPUTransferBuffer(v.device, bd.tex_transfer_buffer)
		bd.tex_transfer_buffer = nil
	}
    if bd.vertex_shader != nil {
		sdl.ReleaseGPUShader(v.device, bd.vertex_shader)
		bd.vertex_shader = nil
	}
    if bd.fragment_shader != nil {
		sdl.ReleaseGPUShader(v.device, bd.fragment_shader)
		bd.fragment_shader = nil
	}
    if bd.tex_sampler_linear != nil {
		sdl.ReleaseGPUSampler(v.device, bd.tex_sampler_linear)
		bd.tex_sampler_linear = nil
	}
    if (bd.pipeline != nil) {
		sdl.ReleaseGPUGraphicsPipeline(v.device, bd.pipeline)
		bd.pipeline = nil
	}
}

ImGui_ImplSDLGPU3_Init :: proc(info : ^ImGui_ImplSDLGPU3_InitInfo) -> bool {
	io := im.GetIO()
    im.CHECKVERSION()
    assert(io.BackendRendererUserData == nil, "Already initialized a renderer backend!")

    // Setup backend capabilities flags
    bd := new(ImGui_ImplSDLGPU3_Data)
    io.BackendRendererUserData = cast(rawptr)bd
    io.BackendRendererName = "imgui_impl_sdlgpu3"
    io.BackendFlags |= {.RendererHasVtxOffset}  // We can honor the ImDrawCmd::VtxOffset field, allowing for large meshes.
    io.BackendFlags |= {.RendererHasTextures}   // We can honor ImGuiPlatformIO::Textures[] requests during render.
    io.BackendFlags |= {.RendererHasViewports}  // We can create multi-viewports on the Renderer side (optional)

    assert(info.device != nil)
    assert(info.color_target_format != .INVALID)

    bd.init_info = info^

    ImGui_ImplSDLGPU3_InitMultiViewportSupport()

    return true
}

ImGui_ImplSDLGPU3_Shutdown :: proc() {
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    assert(bd != nil, "No renderer backend to shutdown, or already shutdown?")
    io := im.GetIO()
    platform_io := im.GetPlatformIO()

    ImGui_ImplSDLGPU3_ShutdownMultiViewportSupport()
    ImGui_ImplSDLGPU3_DestroyDeviceObjects()

    io.BackendRendererName = nil
    io.BackendRendererUserData = nil
    io.BackendFlags &= ~{.RendererHasVtxOffset, .RendererHasTextures, .RendererHasViewports}
    im.PlatformIO_ClearRendererHandlers(platform_io)
    free(bd)
}

ImGui_ImplSDLGPU3_NewFrame :: proc() {
	bd := ImGui_ImplSDLGPU3_GetBackendData()
    assert(bd != nil, "Context or backend not initialized! Did you call ImGui_ImplSDLGPU3_Init()?")

    if bd.tex_sampler_linear == nil {
        ImGui_ImplSDLGPU3_CreateDeviceObjects()
	}
}

//--------------------------------------------------------------------------------------------------------
// MULTI-VIEWPORT / PLATFORM INTERFACE SUPPORT
// This is an _advanced_ and _optional_ feature, allowing the backend to create and handle multiple viewports simultaneously.
// If you are new to dear imgui or creating a new binding for dear imgui, it is recommended that you completely ignore this section first..
//--------------------------------------------------------------------------------------------------------

ImGui_ImplSDLGPU3_CreateWindow :: proc "c" (viewport : ^im.Viewport) {
	context = runtime.default_context()
	data := ImGui_ImplSDLGPU3_GetBackendData()
    window := sdl.GetWindowFromID(cast(sdl.WindowID)cast(uintptr)viewport.PlatformHandle)
    if !sdl.ClaimWindowForGPUDevice(data.init_info.device, window) {
		// TODO: log
		fmt.println("sdl.ClaimWindowForGPUDevice() failed:", sdl.GetError())
	}
    if !sdl.SetGPUSwapchainParameters(data.init_info.device, window, data.init_info.swapchain_composition,
	data.init_info.present_mode) {
		// TODO: log
		fmt.println("sdl.SetGPUSwapchainParameters() failed:", sdl.GetError())
	}
    viewport.RendererUserData = cast(rawptr)cast(uintptr)1
}

ImGui_ImplSDLGPU3_RenderWindow :: proc "c" (viewport : ^im.Viewport, d : rawptr) {
	context = runtime.default_context()
	data := ImGui_ImplSDLGPU3_GetBackendData()
    window := sdl.GetWindowFromID(cast(sdl.WindowID)cast(uintptr)viewport.PlatformHandle)

    draw_data := viewport.DrawData_

    command_buffer := sdl.AcquireGPUCommandBuffer(data.init_info.device)

    swapchain_texture : ^sdl.GPUTexture
    if !sdl.AcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, nil, nil) {
		// TODO: log
		fmt.println("sdl.AcquireGPUSwapchainTexture() failed:", sdl.GetError())
	}

    if swapchain_texture != nil {
        ImGui_ImplSDLGPU3_PrepareDrawData(draw_data, command_buffer) // FIXME-OPT: Not optimal, may this be done earlier?
        target_info : sdl.GPUColorTargetInfo
        target_info.texture = swapchain_texture
        target_info.clear_color = sdl.FColor{ 0.0,0.0,0.0,1.0 }
        target_info.load_op = .CLEAR
        target_info.store_op = .STORE
        target_info.mip_level = 0
        target_info.layer_or_depth_plane = 0
        target_info.cycle = false
        render_pass := sdl.BeginGPURenderPass(command_buffer, &target_info, 1, nil)
        ImGui_ImplSDLGPU3_RenderDrawData(draw_data, command_buffer, render_pass)
        sdl.EndGPURenderPass(render_pass)
    }

    if !sdl.SubmitGPUCommandBuffer(command_buffer) {
		// TODO: log
		fmt.println("sdl.SubmitGPUCommandBuffer() failed:", sdl.GetError())
	}
}

ImGui_ImplSDLGPU3_DestroyWindow :: proc "c" (viewport : ^im.Viewport) {
	data := ImGui_ImplSDLGPU3_GetBackendData()
    if viewport.RendererUserData != nil {
		window := sdl.GetWindowFromID(cast(sdl.WindowID)cast(uintptr)viewport.PlatformHandle)
        sdl.ReleaseWindowFromGPUDevice(data.init_info.device, window)
    }
    viewport.RendererUserData = nil
}

ImGui_ImplSDLGPU3_InitMultiViewportSupport :: proc() {
	platform_io := im.GetPlatformIO()
    platform_io.Renderer_RenderWindow = ImGui_ImplSDLGPU3_RenderWindow
    platform_io.Renderer_CreateWindow = ImGui_ImplSDLGPU3_CreateWindow
    platform_io.Renderer_DestroyWindow = ImGui_ImplSDLGPU3_DestroyWindow
}

ImGui_ImplSDLGPU3_ShutdownMultiViewportSupport :: proc() {
    im.DestroyPlatformWindows()
}
