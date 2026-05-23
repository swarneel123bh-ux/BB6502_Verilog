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

  // Cursor block
  SDL_SetRenderDrawColor(r, 100, 200, 100, 180);
  SDL_Rect cur = { cur_col * CELL_W, cur_row * CELL_H, CELL_W, CELL_H };
  SDL_RenderFillRect(r, &cur);

  SDL_RenderPresent(r);
}

int main(int argc, char** argv) {
  const char* font_path = (argc > 1) ? argv[1]
    : "/System/Library/Fonts/Menlo.ttc";   // macOS default; change on Linux

  if (SDL_Init(SDL_INIT_VIDEO) < 0) {
    fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
    return 1;
  }
  if (TTF_Init() < 0) {
    fprintf(stderr, "TTF_Init: %s\n", TTF_GetError());
    return 1;
  }

  TTF_Font* font = TTF_OpenFont(font_path, 14);
  if (!font) {
    fprintf(stderr, "TTF_OpenFont(%s): %s\n", font_path, TTF_GetError());
    return 1;
  }

  SDL_Window* win = SDL_CreateWindow("BB6502 monitor",
    SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WIN_W, WIN_H, 0);
  SDL_Renderer* ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);

  // Open FIFO non-blocking. O_RDWR (instead of O_RDONLY) prevents EOF when
  // the writer transiently closes, since we also hold the write end.
  int fd = open("/tmp/bb6502_gpu", O_RDWR | O_NONBLOCK);
  if (fd < 0) { perror("open /tmp/bb6502_gpu"); return 1; }

  memset(screen, 0, sizeof(screen));
  int running = 1;
  while (running) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
      if (e.type == SDL_QUIT) running = 0;
    }

    char buf[512];
    ssize_t n = read(fd, buf, sizeof(buf));
    if (n > 0) {
      for (ssize_t i = 0; i < n; i++) put_char(buf[i]);
    }

    render(ren, font);
    SDL_Delay(16);   // ~60 fps
  }

  close(fd);
  TTF_CloseFont(font);
  SDL_DestroyRenderer(ren);
  SDL_DestroyWindow(win);
  TTF_Quit();
  SDL_Quit();
  return 0;
}
