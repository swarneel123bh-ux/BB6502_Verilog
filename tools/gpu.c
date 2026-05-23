#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define COLS    80
#define ROWS    25
#define CELL_W  10
#define CELL_H  18
#define WIN_W   (COLS * CELL_W)
#define WIN_H   (ROWS * CELL_H)

static char screen[ROWS][COLS];
static int  cur_row = 0, cur_col = 0;

static void scroll_if_needed(void) {
  if (cur_row >= ROWS) {
    memmove(screen[0], screen[1], (ROWS - 1) * COLS);
    memset(screen[ROWS - 1], 0, COLS);
    cur_row = ROWS - 1;
  }
}

static void put_char(char c) {
  if (c == '\n')        { cur_row++; cur_col = 0; }
  else if (c == '\r')   { cur_col = 0; }
  else if (c == '\b')   { if (cur_col > 0) { cur_col--; screen[cur_row][cur_col] = ' '; } }
  else if (c == '\f')   { memset(screen, 0, sizeof(screen)); cur_row = cur_col = 0; }
  else if (c >= ' ' && c < 127) {
    screen[cur_row][cur_col++] = c;
    if (cur_col >= COLS) { cur_col = 0; cur_row++; }
  }
  scroll_if_needed();
}

static void render(SDL_Renderer* r, TTF_Font* f) {
  SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
  SDL_RenderClear(r);

  SDL_Color fg = { 200, 220, 200, 255 };
  for (int row = 0; row < ROWS; row++) {
    char line[COLS + 1];
    int len = 0;
    for (int col = 0; col < COLS; col++) {
      char c = screen[row][col];
      line[len++] = (c == 0) ? ' ' : c;
    }
    line[len] = 0;
    SDL_Surface* surf = TTF_RenderText_Solid(f, line, fg);
    if (surf) {
      SDL_Texture* tex = SDL_CreateTextureFromSurface(r, surf);
      SDL_Rect dst = { 0, row * CELL_H, surf->w, surf->h };
      SDL_RenderCopy(r, tex, NULL, &dst);
      SDL_DestroyTexture(tex);
      SDL_FreeSurface(surf);
    }
  }

  SDL_SetRenderDrawColor(r, 100, 200, 100, 180);
  SDL_Rect cur = { cur_col * CELL_W, cur_row * CELL_H, CELL_W, CELL_H };
  SDL_RenderFillRect(r, &cur);

  SDL_RenderPresent(r);
}

// Write a single byte to the input FIFO. Drop on failure (e.g., no reader yet).
static void send_byte(int fd, unsigned char c) {
  if (fd < 0) return;
  ssize_t r = write(fd, &c, 1);
  (void)r;
}

int main(int argc, char** argv) {
  const char* font_path = (argc > 1) ? argv[1]
    : "/System/Library/Fonts/Menlo.ttc";

  if (SDL_Init(SDL_INIT_VIDEO) < 0) {
    fprintf(stderr, "SDL_Init: %s\n", SDL_GetError()); return 1;
  }
  if (TTF_Init() < 0) {
    fprintf(stderr, "TTF_Init: %s\n", TTF_GetError()); return 1;
  }

  TTF_Font* font = TTF_OpenFont(font_path, 14);
  if (!font) {
    fprintf(stderr, "TTF_OpenFont(%s): %s\n", font_path, TTF_GetError());
    return 1;
  }

  SDL_Window* win = SDL_CreateWindow("BB6502 monitor",
    SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WIN_W, WIN_H, 0);
  SDL_Renderer* ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);

  // Output FIFO: bytes from simulated GPU UART -> screen
  int gpu_fd = open("/tmp/bb6502_gpu", O_RDWR | O_NONBLOCK);
  if (gpu_fd < 0) { perror("open /tmp/bb6502_gpu"); return 1; }

  // Input FIFO: keystrokes -> simulated ACIA RX
  // O_RDWR | O_NONBLOCK opens without blocking even if no reader is attached yet.
  // Use a regular file, truncated at startup. The simulation polls it by
  // fseek+fgetc each time, which doesn't block when at EOF.
  int in_fd = open("/tmp/bb6502_in", O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
  if (in_fd < 0) { perror("open /tmp/bb6502_in"); return 1; }

  // Enable SDL_TEXTINPUT events for printable characters (handles shift/locale).
  SDL_StartTextInput();

  memset(screen, 0, sizeof(screen));
  int running = 1;
  while (running) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
      switch (e.type) {
        case SDL_QUIT:
          running = 0;
          break;

        case SDL_TEXTINPUT:
          // e.text.text is a null-terminated UTF-8 string, usually 1 byte for ASCII.
          for (char* p = e.text.text; *p; p++) {
            if ((unsigned char)*p < 128) send_byte(in_fd, *p);
          }
          break;

        case SDL_KEYDOWN: {
          SDL_Keycode k    = e.key.keysym.sym;
          Uint16     mod   = e.key.keysym.mod;
          unsigned char ch = 0;

          if (mod & (KMOD_CTRL)) {
            // Ctrl + letter -> 0x01..0x1A
            if (k >= SDLK_a && k <= SDLK_z) ch = (k - SDLK_a) + 1;
          } else {
            switch (k) {
              case SDLK_RETURN:    ch = '\r'; break;
              case SDLK_BACKSPACE: ch = 0x08; break;
              case SDLK_TAB:       ch = '\t'; break;
              case SDLK_ESCAPE:    ch = 0x1b; break;
              default:             ch = 0;    break;  // printables handled by TEXTINPUT
            }
          }
          if (ch != 0) send_byte(in_fd, ch);
          break;
        }
      }
    }

    char buf[512];
    ssize_t n = read(gpu_fd, buf, sizeof(buf));
    if (n > 0) for (ssize_t i = 0; i < n; i++) put_char(buf[i]);

    render(ren, font);
    SDL_Delay(16);
  }

  SDL_StopTextInput();
  close(gpu_fd);
  close(in_fd);
  TTF_CloseFont(font);
  SDL_DestroyRenderer(ren);
  SDL_DestroyWindow(win);
  TTF_Quit();
  SDL_Quit();
  return 0;
}
