import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Track } from "../../src/player";

type PlayerModule = typeof import("../../src/player");
type Invoke = (cmd: string, args?: Record<string, unknown>) => unknown;

function track(id: string, title = `track ${id}`): Track {
  return {
    id,
    title,
    webpage_url: `https://www.youtube.com/watch?v=${id}`,
    thumbnail_url: null,
  };
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T) => void;
  reject: (reason?: unknown) => void;
} {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

async function setupPlayer({
  invoke = () => undefined,
  isTauri = true,
  currentTime = 0,
  restartResult = false,
  pauseResult = true,
}: {
  invoke?: Invoke;
  isTauri?: boolean;
  currentTime?: number;
  restartResult?: boolean;
  pauseResult?: boolean;
} = {}): Promise<{
  player: PlayerModule;
  invokeMock: ReturnType<typeof vi.fn>;
  audio: {
    stop: ReturnType<typeof vi.fn>;
    setOnEnded: ReturnType<typeof vi.fn>;
    playPath: ReturnType<typeof vi.fn>;
    restart: ReturnType<typeof vi.fn>;
    togglePause: ReturnType<typeof vi.fn>;
    currentTime: ReturnType<typeof vi.fn>;
  };
  emitProgress: (percent: number) => void;
}> {
  vi.resetModules();

  let progressHandler: ((event: { payload: number }) => void) | null = null;
  const invokeMock = vi.fn(invoke);
  const audio = {
    stop: vi.fn(),
    setOnEnded: vi.fn(),
    playPath: vi.fn(async () => {}),
    restart: vi.fn(async () => restartResult),
    togglePause: vi.fn(async () => pauseResult),
    currentTime: vi.fn(() => currentTime),
  };

  vi.doMock("../../src/tauri", () => ({
    invoke: invokeMock,
    isTauri: () => isTauri,
    listen: vi.fn(
      (_event: string, handler: (event: { payload: number }) => void) => {
        if (_event === "download-progress") progressHandler = handler;
        return Promise.resolve(() => {});
      },
    ),
  }));
  vi.doMock("../../src/audio", () => audio);

  return {
    player: await import("../../src/player"),
    invokeMock,
    audio,
    emitProgress: (percent: number) => progressHandler?.({ payload: percent }),
  };
}

beforeEach(() => {
  vi.restoreAllMocks();
});

describe("parseStartSeconds", () => {
  it("parses numeric and h/m/s YouTube timecodes", async () => {
    const { player } = await setupPlayer();

    expect(player.parseStartSeconds("https://youtu.be/aaaaaaaaaaa?t=90")).toBe(
      90,
    );
    expect(
      player.parseStartSeconds("https://youtu.be/aaaaaaaaaaa?t=1h2m3s"),
    ).toBe(3723);
    expect(
      player.parseStartSeconds(
        "https://youtube.com/watch?v=aaaaaaaaaaa&start=7",
      ),
    ).toBe(7);
  });

  it("ignores malformed URLs and malformed timecodes", async () => {
    const { player } = await setupPlayer();

    expect(player.parseStartSeconds("not a url")).toBe(0);
    expect(
      player.parseStartSeconds("https://youtu.be/aaaaaaaaaaa?t=soon"),
    ).toBe(0);
  });
});

describe("looksLikeUrl", () => {
  it("accepts http(s) URLs and rejects stray text", async () => {
    const { player } = await setupPlayer();

    expect(player.looksLikeUrl("https://youtu.be/aaaaaaaaaaa")).toBe(true);
    expect(player.looksLikeUrl("https://soundcloud.com/artist/track")).toBe(
      true,
    );
    expect(player.looksLikeUrl("  http://example.com/x  ")).toBe(true);
    expect(player.looksLikeUrl("just some copied text")).toBe(false);
    expect(player.looksLikeUrl("file:///etc/passwd")).toBe(false);
    expect(player.looksLikeUrl("")).toBe(false);
  });
});

describe("load", () => {
  it("uses cached audio for direct video URLs and applies the URL timecode", async () => {
    const videoId = "aaaaaaaaaaa";
    const { player, invokeMock, audio } = await setupPlayer({
      invoke: (cmd) => {
        if (cmd === "cached_audio")
          return Promise.resolve({ path: "/cache/a.m4a", title: "cached cut" });
        if (cmd === "cancel_download") return Promise.resolve();
        throw new Error(`unexpected ${cmd}`);
      },
    });

    await player.load(`https://youtu.be/${videoId}?t=1m30s`);

    expect(player.getQueue()).toEqual([
      {
        id: videoId,
        title: "cached cut",
        webpage_url: `https://youtu.be/${videoId}?t=1m30s`,
        thumbnail_url: null,
      },
    ]);
    expect(player.getStatus()).toBe("playing");
    expect(audio.playPath).toHaveBeenCalledWith(
      "/cache/a.m4a",
      90,
      expect.any(Function),
    );
    expect(invokeMock).not.toHaveBeenCalledWith(
      "resolve_tracks",
      expect.anything(),
    );
  });

  it("sets failed status and rethrows resolver errors", async () => {
    const { player } = await setupPlayer({
      invoke: (cmd) => {
        if (cmd === "resolve_tracks") return Promise.reject("yt-dlp stderr");
        throw new Error(`unexpected ${cmd}`);
      },
    });

    await expect(
      player.load("https://youtube.com/playlist?list=demo"),
    ).rejects.toBe("yt-dlp stderr");
    expect(player.getStatus()).toBe("failed");
  });

  it("surfaces download progress from the Tauri event listener", async () => {
    const { player, emitProgress } = await setupPlayer();
    const onProgress = vi.fn();

    player.setOnProgress(onProgress);
    emitProgress(42.4);

    expect(onProgress).toHaveBeenCalledWith(42.4);
  });
});

describe("playIndex", () => {
  it("does not play an older download after a newer selection wins", async () => {
    const first = deferred<string>();
    const tracks = [track("aaaaaaaaaaa"), track("bbbbbbbbbbb")];
    const { player, invokeMock, audio } = await setupPlayer({
      invoke: (cmd, args) => {
        if (cmd === "resolve_tracks") return Promise.resolve(tracks);
        if (cmd === "download_audio") {
          return (args?.videoId as string) === "aaaaaaaaaaa"
            ? first.promise
            : Promise.resolve("/cache/b.m4a");
        }
        throw new Error(`unexpected ${cmd}`);
      },
    });

    const loading = player.load("https://youtube.com/playlist?list=demo");
    await vi.waitFor(() =>
      expect(invokeMock).toHaveBeenCalledWith("download_audio", {
        videoUrl: tracks[0].webpage_url,
        videoId: tracks[0].id,
        emitProgress: true,
      }),
    );
    expect(player.isDownloading()).toBe(true); // a download is in flight

    await player.playIndex(1);
    first.resolve("/cache/a.m4a");
    await loading;

    expect(player.isDownloading()).toBe(false); // both downloads settled

    expect(audio.playPath).toHaveBeenCalledTimes(1);
    expect(audio.playPath).toHaveBeenCalledWith(
      "/cache/b.m4a",
      0,
      expect.any(Function),
    );
    expect(player.getIndex()).toBe(1);
  });

  it("wraps at the end when queue repeat is enabled", async () => {
    const tracks = [track("aaaaaaaaaaa"), track("bbbbbbbbbbb")];
    const { player, audio } = await setupPlayer({
      invoke: (cmd, args) => {
        if (cmd === "resolve_tracks") return Promise.resolve(tracks);
        if (cmd === "download_audio")
          return Promise.resolve(`/cache/${args?.videoId}.m4a`);
        if (cmd === "cancel_download") return Promise.resolve();
        throw new Error(`unexpected ${cmd}`);
      },
    });

    await player.load("https://youtube.com/playlist?list=demo");
    await player.skipNext();
    expect(player.getIndex()).toBe(1);

    expect(player.toggleRepeat()).toBe("queue");
    await player.next(true);

    expect(player.getIndex()).toBe(0);
    expect(audio.playPath).toHaveBeenLastCalledWith(
      "/cache/aaaaaaaaaaa.m4a",
      0,
      expect.any(Function),
    );
  });

  it("prefetches the next two tracks and stops at the lookahead window", async () => {
    const tracks = [
      track("aaaaaaaaaaa"),
      track("bbbbbbbbbbb"),
      track("ccccccccccc"),
      track("ddddddddddd"),
    ];
    const { player, invokeMock } = await setupPlayer({
      invoke: (cmd, args) => {
        if (cmd === "resolve_tracks") return Promise.resolve(tracks);
        if (cmd === "download_audio")
          return Promise.resolve(`/cache/${args?.videoId}.m4a`);
        throw new Error(`unexpected ${cmd}`);
      },
    });

    await player.load("https://youtube.com/playlist?list=demo");

    await vi.waitFor(() =>
      expect(invokeMock).toHaveBeenCalledWith("download_audio", {
        videoUrl: tracks[2].webpage_url,
        videoId: tracks[2].id,
        emitProgress: true,
      }),
    );
    expect(invokeMock).toHaveBeenCalledWith("download_audio", {
      videoUrl: tracks[0].webpage_url,
      videoId: tracks[0].id,
      emitProgress: true,
    });
    expect(invokeMock).toHaveBeenCalledWith("download_audio", {
      videoUrl: tracks[1].webpage_url,
      videoId: tracks[1].id,
      emitProgress: true,
    });
    expect(invokeMock).not.toHaveBeenCalledWith("download_audio", {
      videoUrl: tracks[3].webpage_url,
      videoId: tracks[3].id,
      emitProgress: true,
    });
  });
});

describe("prev", () => {
  it("restarts the current track when past the restart threshold", async () => {
    const tracks = [track("aaaaaaaaaaa"), track("bbbbbbbbbbb")];
    const { player, audio } = await setupPlayer({
      currentTime: 3,
      restartResult: true,
      invoke: (cmd, args) => {
        if (cmd === "resolve_tracks") return Promise.resolve(tracks);
        if (cmd === "download_audio")
          return Promise.resolve(`/cache/${args?.videoId}.m4a`);
        if (cmd === "cancel_download") return Promise.resolve();
        throw new Error(`unexpected ${cmd}`);
      },
    });

    await player.load("https://youtube.com/playlist?list=demo");
    await player.skipNext();
    await player.prev();

    expect(audio.restart).toHaveBeenCalledOnce();
    expect(player.getIndex()).toBe(1);
    expect(player.getStatus()).toBe("playing");
  });
});
