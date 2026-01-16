package game

import sdl "vendor:sdl3"
import im "deps:odin-imgui"

// From imgui_impl_sdlrenderer3.h
// [BETA] Selected render state data shared with callbacks.
// This is temporarily stored in GetPlatformIO().Renderer_RenderState during the ImGui_ImplSDLRenderer3_RenderDrawData() call.
// (Please open an issue if you feel you need access to more data)
ImGui_ImplSDLRenderer3_RenderState :: struct {
	renderer : ^sdl.Renderer,
}

// From imgui_impl_sdlrenderer3.cpp

// dear imgui: Renderer Backend for SDL_Renderer for SDL3
// (Requires: SDL 3.1.8+)

// Note that SDL_Renderer is an _optional_ component of SDL3, which IMHO is now largely obsolete.
// For a multi-platform app consider using other technologies:
// - SDL3+SDL_GPU: SDL_GPU is SDL3 new graphics abstraction API.
// - SDL3+DirectX, SDL3+OpenGL, SDL3+Vulkan: combine SDL with dedicated renderers.
// If your application wants to render any non trivial amount of graphics other than UI,
// please be aware that SDL_Renderer currently offers a limited graphic API to the end-user
// and it might be difficult to step out of those boundaries.

// Implemented features:
//  [X] Renderer: User texture binding. Use 'SDL_Texture*' as texture identifier. Read the FAQ about ImTextureID/ImTextureRef!
//  [X] Renderer: Large meshes support (64k+ vertices) even with 16-bit indices (ImGuiBackendFlags_RendererHasVtxOffset).
//  [X] Renderer: Texture updates support for dynamic font atlas (ImGuiBackendFlags_RendererHasTextures).
//  [X] Renderer: Expose selected render state for draw callbacks to use. Access in '(ImGui_ImplXXXX_RenderState*)GetPlatformIO().Renderer_RenderState'.
// Missing features:
//  [ ] Renderer: Multi-viewport support (multiple windows).

// You can copy and use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// CHANGELOG
//  2025-09-18: Call platform_io.ClearRendererHandlers() on shutdown.
//  2025-06-11: Added support for ImGuiBackendFlags_RendererHasTextures, for dynamic font atlas. Removed ImGui_ImplSDLRenderer3_CreateFontsTexture() and ImGui_ImplSDLRenderer3_DestroyFontsTexture().
//  2025-01-18: Use endian-dependent RGBA32 texture format, to match SDL_Color.
//  2024-10-09: Expose selected render state in ImGui_ImplSDLRenderer3_RenderState, which you can access in 'void* platform_io.Renderer_RenderState' during draw callbacks.
//  2024-07-01: Update for SDL3 api changes: SDL_RenderGeometryRaw() uint32 version was removed (SDL#9009).
//  2024-05-14: *BREAKING CHANGE* ImGui_ImplSDLRenderer3_RenderDrawData() requires SDL_Renderer* passed as parameter.
//  2024-02-12: Amend to query SDL_RenderViewportSet() and restore viewport accordingly.
//  2023-05-30: Initial version.

// SDL_Renderer data
ImGui_ImplSDLRenderer3_Data :: struct {
	renderer : ^sdl.Renderer,       // Main viewport's renderer
	// @ph_begin
	// dear_bindings doesn't providing an interface to interact with ImVector<T> types so we will
	// handle them here and then assign to Size,Capacity,Data as needed
    color_buffer : [dynamic]sdl.FColor,
	// @ph_end
}

// Backend data stored in io.BackendRendererUserData to allow support for multiple Dear ImGui contexts
// It is STRONGLY preferred that you use docking branch with multi-viewports (== single Dear ImGui context + multiple windows) instead of multiple Dear ImGui contexts.
ImGui_ImplSDLRenderer3_GetBackendData :: proc "contextless" () -> ^ImGui_ImplSDLRenderer3_Data {
    return im.GetCurrentContext() != nil ? (^ImGui_ImplSDLRenderer3_Data)(im.GetIO().BackendRendererUserData) : nil
}

// Functions
ImGui_ImplSDLRenderer3_Init:: proc(renderer : ^sdl.Renderer) -> bool {
	io := im.GetIO()
    im.CHECKVERSION()
    assert(io.BackendRendererUserData == nil, "Already initialized a renderer backend!")
    assert(renderer != nil, "SDL_Renderer not initialized!")

    // Setup backend capabilities flags
	bd := new(ImGui_ImplSDLRenderer3_Data)
    io.BackendRendererUserData = cast(rawptr)bd
    io.BackendRendererName = "imgui_impl_sdlrenderer3"
    io.BackendFlags |= {.RendererHasVtxOffset}  // We can honor the ImDrawCmd::VtxOffset field, allowing for large meshes.
    io.BackendFlags |= {.RendererHasTextures}   // We can honor ImGuiPlatformIO::Textures[] requests during render.
    bd.renderer = renderer

    return true
}

ImGui_ImplSDLRenderer3_Shutdown :: proc() {
	bd := ImGui_ImplSDLRenderer3_GetBackendData()
    assert(bd != nil, "No renderer backend to shutdown, or already shutdown?")
    io := im.GetIO()
    platform_io := im.GetPlatformIO()

    ImGui_ImplSDLRenderer3_DestroyDeviceObjects()

    io.BackendRendererName = nil
    io.BackendRendererUserData = nil
    io.BackendFlags &= ~{.RendererHasVtxOffset, .RendererHasTextures}
	im.PlatformIO_ClearRendererHandlers(platform_io)
    free(bd)
}

ImGui_ImplSDLRenderer3_SetupRenderState :: proc(renderer : ^sdl.Renderer) {
    // Clear out any viewports and cliprect set by the user
    // FIXME: Technically speaking there are lots of other things we could backup/setup/restore during our render process.
    sdl.SetRenderViewport(renderer, nil)
    sdl.SetRenderClipRect(renderer, nil)
}

ImGui_ImplSDLRenderer3_NewFrame :: proc() {
	bd := ImGui_ImplSDLRenderer3_GetBackendData()
    assert(bd != nil, "Context or backend not initialized! Did you call ImGui_ImplSDLRenderer3_Init()?")
}

// @phbegin Note that we changed the return type here from int to bool to match sdl.RenderGeoemtryRaw return type
// https://github.com/libsdl-org/SDL/issues/9009
SDL_RenderGeometryRaw8BitColor :: proc(renderer : ^sdl.Renderer, colors_out : ^[dynamic]sdl.FColor, texture : ^sdl.Texture, xy : ^f32, xy_stride : i32, color : [^]sdl.Color, color_stride : i32, uv : ^f32, uv_stride : i32, num_vertices : i32, indices : rawptr, num_indices : i32, size_indices : i32) -> bool {
	resize(colors_out, num_vertices)
	for i in 0..<num_vertices {
		c := color[i*(color_stride/4)]
        colors_out[i].r = f32(c.r) / 255.0
        colors_out[i].g = f32(c.g) / 255.0
        colors_out[i].b = f32(c.b) / 255.0
        colors_out[i].a = f32(c.a) / 255.0
    }
    return sdl.RenderGeometryRaw(renderer, texture, xy, xy_stride, raw_data(colors_out^), size_of(sdl.FColor), uv, uv_stride, num_vertices, indices, num_indices, size_indices)
}

ImGui_ImplSDLRenderer3_RenderDrawData :: proc(draw_data : ^im.DrawData, renderer : ^sdl.Renderer) {
	bd := ImGui_ImplSDLRenderer3_GetBackendData()

    // If there's a scale factor set by the user, use that instead
    // If the user has specified a scale factor to SDL_Renderer already via SDL_RenderSetScale(), SDL will scale whatever we pass
    // to SDL_RenderGeometryRaw() by that scale factor. In that case we don't want to be also scaling it ourselves here.
    rsx : f32 = 1.0
    rsy : f32 = 1.0
    sdl.GetRenderScale(renderer, &rsx, &rsy)
    render_scale : im.Vec2
    render_scale.x = (rsx == 1.0) ? draw_data.FramebufferScale.x : 1.0
    render_scale.y = (rsy == 1.0) ? draw_data.FramebufferScale.y : 1.0

    // Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    fb_width : int = cast(int)(draw_data.DisplaySize.x * render_scale.x)
	fb_height : int = cast(int)(draw_data.DisplaySize.y * render_scale.y)
    if fb_width == 0 || fb_height == 0 {
        return
	}

    // Catch up with texture updates. Most of the times, the list will have 1 element with an OK status, aka nothing to do.
    // (This almost always points to ImGui::GetPlatformIO().Textures[] but is part of ImDrawData to allow overriding or disabling texture updates).
    if draw_data.Textures != nil {
        for tex_idx in 0..<draw_data.Textures.Size {
			tex := (cast([^]^im.TextureData)draw_data.Textures.Data)[tex_idx]
            if tex.Status != .OK {
                ImGui_ImplSDLRenderer3_UpdateTexture(tex)
			}
		}
	}

    // Backup SDL_Renderer state that will be modified to restore it afterwards
	BackupSDLRendererState :: struct {
		viewport : sdl.Rect,
        viewport_enabled : bool,
        clip_enabled : bool,
        clip_rect : sdl.Rect,
    }
	old : BackupSDLRendererState
    old.viewport_enabled = sdl.RenderViewportSet(renderer)
    old.clip_enabled = sdl.RenderClipEnabled(renderer)
    sdl.GetRenderViewport(renderer, &old.viewport)
    sdl.GetRenderClipRect(renderer, &old.clip_rect)

    // Setup desired state
    ImGui_ImplSDLRenderer3_SetupRenderState(renderer)

    // Setup render state structure (for callbacks and custom texture bindings)
    platform_io := im.GetPlatformIO()
    render_state : ImGui_ImplSDLRenderer3_RenderState
    render_state.renderer = renderer
    platform_io.Renderer_RenderState = &render_state

    // Will project scissor/clipping rectangles into framebuffer space
    clip_off := draw_data.DisplayPos         // (0,0) unless using multi-viewports
    clip_scale := render_scale

	// TODO: Keep porting here
    // Render command lists
    for draw_list_idx in 0..<draw_data.CmdLists.Size {
		draw_list := (cast([^]^im.DrawList)draw_data.CmdLists.Data)[draw_list_idx]

        vtx_buffer := cast([^]im.DrawVert)draw_list.VtxBuffer.Data
		idx_buffer := cast([^]im.DrawIdx)draw_list.IdxBuffer.Data

        for cmd_i : i32 = 0; cmd_i < draw_list.CmdBuffer.Size; cmd_i += 1 {
			pcmd := &(cast([^]im.DrawCmd)draw_list.CmdBuffer.Data)[cmd_i]
            if pcmd.UserCallback != nil {
                // User callback, registered via ImDrawList::AddCallback()
                // (ImDrawCallback_ResetRenderState is a special callback value used by the user to request the renderer to reset render state.)
				// TODO: Is this the correct hacky check here?
				// if pcmd.UserCallback == ImDrawCallback_ResetRenderState
                if cast(int)cast(uintptr)cast(rawptr)pcmd.UserCallback == IMDRAWCALLBACK_RESETRENDERSTATE {
                    ImGui_ImplSDLRenderer3_SetupRenderState(renderer)
				} else {
                    pcmd.UserCallback(draw_list, pcmd)
				}
            } else {
                // Project scissor/clipping rectangles into framebuffer space
				clip_min := im.Vec2{(pcmd.ClipRect.x - clip_off.x) * clip_scale.x, (pcmd.ClipRect.y - clip_off.y) * clip_scale.y}
				clip_max := im.Vec2{(pcmd.ClipRect.z - clip_off.x) * clip_scale.x, (pcmd.ClipRect.w - clip_off.y) * clip_scale.y}
                if clip_min.x < 0.0 { clip_min.x = 0.0 }
                if clip_min.y < 0.0 { clip_min.y = 0.0 }
                if clip_max.x > f32(fb_width) { clip_max.x = cast(f32)fb_width }
                if clip_max.y > f32(fb_height) { clip_max.y = cast(f32)fb_height }
                if clip_max.x <= clip_min.x || clip_max.y <= clip_min.y {
                    continue
				}

				r : sdl.Rect
                r.x = cast(i32)clip_min.x
                r.y = cast(i32)clip_min.y
                r.w = cast(i32)(clip_max.x - clip_min.x)
                r.h = cast(i32)(clip_max.y - clip_min.y)
                sdl.SetRenderClipRect(renderer, &r)

				// TODO: Verify this translation to odin
                xy := &vtx_buffer[pcmd.VtxOffset].pos.x
                uv := &vtx_buffer[pcmd.VtxOffset].uv.x
                color := cast(^sdl.Color)cast(rawptr)(&(vtx_buffer[pcmd.VtxOffset].col)) // SDL 2.0.19+

                // Bind texture, Draw
				tex := cast(^sdl.Texture)cast(uintptr)im.DrawCmd_GetTexID(pcmd)
                SDL_RenderGeometryRaw8BitColor(renderer, &bd.color_buffer, tex,
                    xy, cast(i32)size_of(im.DrawVert),
                    color, cast(i32)size_of(im.DrawVert),
                    uv, cast(i32)size_of(im.DrawVert),
                    draw_list.VtxBuffer.Size - cast(i32)pcmd.VtxOffset,
                    &idx_buffer[pcmd.IdxOffset], cast(i32)pcmd.ElemCount, size_of(im.DrawIdx))
            }
        }
    }
    platform_io.Renderer_RenderState = nil

    // Restore modified SDL_Renderer state
    sdl.SetRenderViewport(renderer, old.viewport_enabled ? &old.viewport : nil)
    sdl.SetRenderClipRect(renderer, old.clip_enabled ? &old.clip_rect : nil)
}

ImGui_ImplSDLRenderer3_UpdateTexture :: proc(tex : ^im.TextureData) {
	bd := ImGui_ImplSDLRenderer3_GetBackendData()

    if tex.Status == .WantCreate {
        // Create and upload new texture to graphics system
        //IMGUI_DEBUG_LOG("UpdateTexture #%03d: WantCreate %dx%d\n", tex->UniqueID, tex->Width, tex->Height);
        assert(tex.TexID == 0 && tex.BackendUserData == nil)
        assert(tex.Format == .RGBA32)

        // Create texture
        // (Bilinear sampling is required by default. Set 'io.Fonts->Flags |= ImFontAtlasFlags_NoBakedLines' or 'style.AntiAliasedLinesUseTex = false' to allow point/nearest sampling)
        sdl_texture := sdl.CreateTexture(bd.renderer, .RGBA32, .STATIC, tex.Width, tex.Height)
        assert(sdl_texture != nil, "Backend failed to create texture!")
        sdl.UpdateTexture(sdl_texture, nil, im.TextureData_GetPixels(tex), im.TextureData_GetPitch(tex))
        sdl.SetTextureBlendMode(sdl_texture, {.BLEND})
        sdl.SetTextureScaleMode(sdl_texture, .LINEAR)

        // Store identifiers
		im.TextureData_SetTexID(tex, cast(im.TextureID)cast(uintptr)sdl_texture)
		im.TextureData_SetStatus(tex, .OK)
    } else if (tex.Status == .WantUpdates) {
        // Update selected blocks. We only ever write to textures regions which have never been used before!
        // This backend choose to use tex->Updates[] but you can use tex->UpdateRect to upload a single region.
		sdl_texture := cast(^sdl.Texture)cast(uintptr)tex.TexID

        for update_idx : i32 = 1; update_idx < tex.Updates.Size; update_idx += 1 {
			r := &(cast([^]im.TextureRect)tex.Updates.Data)[update_idx]
            sdl_r := sdl.Rect{ i32(r.x), i32(r.y), i32(r.w), i32(r.h) }
            sdl.UpdateTexture(sdl_texture, &sdl_r, im.TextureData_GetPixelsAt(tex, i32(r.x), i32(r.y)), im.TextureData_GetPitch(tex))
        }
		im.TextureData_SetStatus(tex, .OK)
    } else if (tex.Status == .WantDestroy) {
        if sdl_texture := cast(^sdl.Texture)cast(uintptr)tex.TexID; sdl_texture != nil {
            sdl.DestroyTexture(sdl_texture)
		}

        // Clear identifiers and mark as destroyed (in order to allow e.g. calling InvalidateDeviceObjects while running)
		im.TextureData_SetTexID(tex, IMTEXTUREID_INVALID)
		im.TextureData_SetStatus(tex, .Destroyed)
    }
}

ImGui_ImplSDLRenderer3_CreateDeviceObjects :: proc() {
}

ImGui_ImplSDLRenderer3_DestroyDeviceObjects :: proc() {
    // Destroy all textures
	platform_io := im.GetPlatformIO()
    for tex_idx in 0..<platform_io.Textures.Size {
		tex := (cast([^]^im.TextureData)platform_io.Textures.Data)[tex_idx]
        if tex.RefCount == 1 {
			im.TextureData_SetStatus(tex, .WantDestroy)
            ImGui_ImplSDLRenderer3_UpdateTexture(tex)
		}
	}
}
