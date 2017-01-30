(*
Copyright (c) 2017 David Pethes

This file is part of RS model viewer.

RS model viewer is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

RS model viewer is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with RS model viewer. If not, see <http://www.gnu.org/licenses/>.
*)
program model_viewer;

uses
  sysutils, math,
  gl, glu, glext, sdl2, imgui, imgui_impl_sdlgl2,
  hob_mesh;

const
  SCR_W_fscrn = 1024;
  SCR_H_fscrn = 768;
  SCR_W_INIT = 1280;
  SCR_H_INIT = 720;
  SCREEN_BPP = 0;
  RotationAngleIncrement = 1;
  ZoomIncrement = 0.3;
  MouseZoomDistanceMultiply = 0.15;
  PitchIncrement = 0.5;
  MouseTranslateMultiply = 0.025;

var
  g_window: PSDL_Window;
  g_ogl_context: TSDL_GLContext;

  model: TModel;

  view: record
      rotation_angle: single;
      distance: single;
      pitch: single;
      x, y: single;
      autorotate: boolean;
      opts: TRenderOpts;
  end;

  key_pressed: record
      wireframe: boolean;
      vcolors: boolean;
      points: boolean;
      textures: boolean;
      fullscreen: boolean;
      autorotate: boolean;
      fg: boolean;
  end;

  mouse: record
      drag: boolean;
      translate: boolean;
      last_x, last_y: integer;
      resume_autorotate_on_release: boolean;
  end;

procedure AppError(s: string);
begin
  writeln(stderr, s);
  halt;
end;


// initial parameters
procedure InitGL;
var
  ogl_info: string;
begin
  ogl_info := format('vendor: %s renderer: %s', [glGetString(GL_VENDOR), glGetString(GL_RENDERER)]);
  writeln(ogl_info);
  ogl_info := 'version: ' + glGetString(GL_VERSION);
  writeln(ogl_info);

  //glShadeModel( GL_SMOOTH );                  // Enable smooth shading
  glClearColor( 0.0, 0.0, 0.0, 0.0 );
  glClearDepth( 1.0 );                        // Depth buffer setup
  glEnable( GL_DEPTH_TEST );                  // Enables Depth Testing
  glDepthFunc( GL_LEQUAL );                   // The Type Of Depth Test To Do
  glHint( GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST );  // Really Nice Perspective Calculations

  //glEnable( GL_CULL_FACE );  //backface culling
  //glCullFace( GL_BACK );

  glEnable(GL_TEXTURE_2D);
end;


// function to reset our viewport after a window resize
procedure SetGLWindowSize( width, height : integer );
begin
  if ( height = 0 ) then
    height := 1;   // Protect against a divide by zero

  glViewport( 0, 0, width, height ); // Setup our viewport.
  glMatrixMode( GL_PROJECTION );     // change to the projection matrix and set our viewing volume.
  glLoadIdentity;
  gluPerspective(45.0, width / height, 0.1, 100.0);  // Set our perspective
 //   glOrtho( 0, width, height, 0, - 1, 1);
  glMatrixMode( GL_MODELVIEW );  // Make sure we're changing the model view and not the projection
  glLoadIdentity;                // Reset The View
end;


// The main drawing function.
procedure DrawGLScene;
begin
  glClear( GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT );
  glLoadIdentity;

  if view.distance < ZoomIncrement then
      view.distance := ZoomIncrement;

  glTranslatef(view.x, view.y, -view.distance);
  glRotatef(view.rotation_angle, 0.0, 1.0, 0.0);
  glRotatef(view.pitch, 1, 0, 0);

  if view.autorotate then
      view.rotation_angle += RotationAngleIncrement;
  if view.rotation_angle > 360 then
      view.rotation_angle -= 360;

  model.DrawGL(view.opts);

  glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
  igRender;
  
  SDL_GL_SwapWindow(g_window);
end;


procedure WindowInit(w_width, w_height: integer);
const
  renderer_index = -1; //The index of the rendering driver to initialize: -1 to initialize the first one supporting the requested flags
var
  ver: TSDL_Version;
  x, y: integer;
  flags: longword;
  io: PImGuiIO;
begin
  SDL_GetVersion(@ver);
  writeln(format('SDL %d.%d.%d', [ver.major, ver.minor, ver.patch]));
  //WriteVideoInfo;

  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE,  24);
  SDL_GL_SetAttribute(SDL_GL_BUFFER_SIZE, 32);
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE,     8);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE,   8);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE,    8);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE,   8);

  WriteLn('init window: ', w_width, 'x', w_height);
  x := SDL_WINDOWPOS_CENTERED;
  y := SDL_WINDOWPOS_CENTERED;
  flags := SDL_WINDOW_SHOWN or SDL_WINDOW_OPENGL or SDL_WINDOW_RESIZABLE;
  g_window := SDL_CreateWindow('RS model viewer', x, y, w_width, w_height, flags);
  if g_window = nil then
      AppError ('SDL_CreateWindow failed. Reason: ' + SDL_GetError());

  g_ogl_context := SDL_GL_CreateContext(g_window);
  if g_ogl_context = nil then begin
      writeln ('SDL_GL_CreateContext failed. Reason: ' + SDL_GetError());
      halt;
  end;
  SDL_GL_SetSwapInterval(1); //enable VSync

  //setup imgui
  io := igGetIO();
  io^.DisplaySize.x := w_width;
  io^.DisplaySize.y := w_height;
  ImGui_ImplSdlGL2_Init();
end;


procedure WindowFree;
begin
  ImGui_ImplSdlGL2_Shutdown();
  SDL_GL_DeleteContext(g_ogl_context);
  SDL_DestroyWindow(g_window);
end;


procedure WindowScreenshot(const width, height : integer);
const
  head: array[0..8] of word = (0, 2, 0, 0, 0, 0, 0, 0, 24);
  counter: integer = 0;
var
  buf: pbyte;
  f: file;
  fname: string;
begin
  buf := getmem(width * height * 4);
  glReadBuffer(GL_FRONT);
  glReadPixels(0, 0, width, height, GL_BGR, GL_UNSIGNED_BYTE, buf);

  fname := format('screenshot_%.4d.tga', [counter]);
  AssignFile(f, fname);
  Rewrite(f, 1);
  head[6] := width;
  head[7] := height;
  BlockWrite(f, head, sizeof(head));
  BlockWrite(f, buf^, width * height * 3);
  CloseFile(f);
  counter += 1;

  Freemem(buf);
end;


procedure InitView;
begin
  view.rotation_angle := 0;
  view.distance := 3;
  view.pitch := 0;
  view.x := 0;
  view.y := 0;
  view.autorotate := true;
  view.opts.wireframe := false;
  view.opts.points := false;
  view.opts.vcolors := true;
  view.opts.textures := true;
end;


procedure HandleEvent(const ev: TSDL_Event; var done: boolean);
var
  io: PImGuiIO;
begin
  ImGui_ImplSdlGL2_ProcessEvent(@ev);
  io := igGetIO();
  if ((ev.type_ = SDL_MOUSEBUTTONDOWN) or
     (ev.type_ = SDL_MOUSEBUTTONUP) or
     (ev.type_ = SDL_MOUSEWHEEL) or
     (ev.type_ = SDL_MOUSEMOTION)) and io^.WantCaptureMouse then
      exit;
  if ((ev.type_ = SDL_KEYDOWN) or (ev.type_ = SDL_KEYUP)) and io^.WantCaptureKeyboard then
      exit;

  case ev.type_ of
      SDL_QUITEV:
          Done := true;
      SDL_WINDOWEVENT: begin
          if ev.window.event = SDL_WINDOWEVENT_RESIZED then
              SetGLWindowSize(ev.window.data1, ev.window.data2);
      end;

      SDL_KEYDOWN: begin
          case ev.key.keysym.sym of
            SDLK_ESCAPE:
                Done := true;
            SDLK_s:
                WindowScreenshot(g_window^.w, g_window^.h);
            SDLK_PAGEUP:
                view.distance += ZoomIncrement;
            SDLK_PAGEDOWN:
                view.distance -= ZoomIncrement;
            SDLK_r:
                if not key_pressed.autorotate then begin
                    view.autorotate := not view.autorotate;
                    key_pressed.autorotate := true;
                end;
                   //model rendering opts
            SDLK_w:
                if not key_pressed.wireframe then begin
                    view.opts.wireframe := not view.opts.wireframe;
                    key_pressed.wireframe := true;
                end;
            SDLK_v:
                if not key_pressed.vcolors then begin
                    view.opts.vcolors := not view.opts.vcolors;
                    key_pressed.vcolors := true;
                end;
            SDLK_p:
                if not key_pressed.points then begin
                    view.opts.points := not view.opts.points;
                    key_pressed.points := true;
                end;
            SDLK_t:
                if not key_pressed.textures then begin
                    view.opts.textures := not view.opts.textures;
                    key_pressed.textures := true;
                end;
            SDLK_LEFT:
                view.opts.fg_to_draw := max(0, view.opts.fg_to_draw - 1);
            SDLK_RIGHT:
                view.opts.fg_to_draw += 1;
          end;
      end;
      SDL_KEYUP: begin
          case ev.key.keysym.sym of
            SDLK_F1:
                key_pressed.fullscreen := false;
            SDLK_w:
                key_pressed.wireframe := false;
            SDLK_v:
                key_pressed.vcolors := false;
            SDLK_p:
                key_pressed.points := false;
            SDLK_t:
                key_pressed.textures := false;
            SDLK_r:
                key_pressed.autorotate := false;
          end;
      end;

      SDL_MOUSEBUTTONDOWN: begin
          mouse.resume_autorotate_on_release := view.autorotate;
          if ev.button.button in [1..3] then begin
              mouse.drag := true;
              mouse.translate := ev.button.button = 2;
              mouse.last_x := ev.button.x;
              mouse.last_y := ev.button.y;
              view.autorotate := false;
          end;
      end;
      SDL_MOUSEBUTTONUP: begin
          mouse.drag := false;
          view.autorotate := mouse.resume_autorotate_on_release;
      end;
      SDL_MOUSEWHEEL: begin
          if ev.wheel.y < 0 then
              view.distance += view.distance * MouseZoomDistanceMultiply;
          if ev.wheel.y > 0 then
              view.distance -= view.distance * MouseZoomDistanceMultiply;
      end;
      SDL_MOUSEMOTION: begin
          if mouse.drag then begin
              if not mouse.translate then begin
                  if ev.motion.y <> mouse.last_y then begin
                      view.pitch += PitchIncrement * ev.motion.yrel;
                      mouse.last_y := ev.motion.y;
                  end;
                  if ev.motion.x <> mouse.last_x then begin
                      view.rotation_angle += RotationAngleIncrement * ev.motion.xrel;
                      mouse.last_x := ev.motion.x;
                  end;
              end else begin
                  if ev.motion.y <> mouse.last_y then begin
                      view.y -= MouseTranslateMultiply * ev.motion.yrel;
                      mouse.last_y := ev.motion.y;
                  end;
                  if ev.motion.x <> mouse.last_x then begin
                      view.x += MouseTranslateMultiply * ev.motion.xrel;
                      mouse.last_x := ev.motion.x;
                  end;
              end;
          end;
      end;
  end; {case}
end;

//******************************************************************************
var
  sec, frames: integer;
  event: TSDL_Event;
  done: boolean;
  hob_file, hmt_file, obj_file: string;

begin
  if Paramcount < 1 then begin
      writeln('specify HOB file');
      exit;
  end;
  hob_file := ParamStr(1);
  hmt_file := StringReplace(hob_file, '.hob', '.hmt', [rfIgnoreCase]);
  model := TModel.Create;
  model.Load(hob_file, hmt_file);

  writeln('Init SDL...');
  SDL_Init(SDL_INIT_VIDEO or SDL_INIT_TIMER);
  WindowInit(SCR_W_INIT, SCR_H_INIT);
  writeln('Init OpenGL...');
  InitGL;
  SetGLWindowSize(g_window^.w, g_window^.h);

  InitView;
  model.InitGL;

  //export
  //obj_file := StringReplace(hob_file, '.hob', '.obj', [rfIgnoreCase]);
  //model.ExportObj(obj_file);

  sec := SDL_GetTicks;
  frames := 0;
  Done := False;
  key_pressed.wireframe := false;
  key_pressed.fullscreen := false;
  while not Done do begin
      ImGui_ImplSdlGL2_NewFrame(g_window);

      igBegin('rendering options');
      igCheckbox('points', @view.opts.points);
      igCheckbox('wireframe', @view.opts.wireframe);
      igCheckbox('textures', @view.opts.textures);
      igCheckbox('vertex colors', @view.opts.vcolors);
      igEnd;

      DrawGLScene;

      while SDL_PollEvent(@event) > 0 do
          HandleEvent(event, done);

      frames += 1;
      if (SDL_GetTicks - sec) >= 1000 then begin
          write(frames:3, ' dist: ', view.distance:5:1, ' rot: ', view.rotation_angle:5:1, #13);
          frames := 0;
          sec := SDL_GetTicks;
      end;
      SDL_Delay(10);
      //WindowScreenshot( surface^.w, surface^.h );
  end;

  model.Free;

  WindowFree;
  SDL_Quit;
end.
