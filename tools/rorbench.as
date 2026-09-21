/*
    rorbench.as - frame-time harness for Experiment 3 of issue #2
    (native D3D9 vs D3D9On12 vs DXVK).

    Samples per-frame delta time after a warm-up window, then reports
    median and 1%-low frame time and quits. Deterministic: same terrain,
    same vehicle, same window length every run.

    Usage:
      RoR.exe -terrain <t> -truck <v> -enter -runscript rorbench.as

    Results land in RoR.log, prefixed "BENCH|" for easy grepping.
*/

array<float> samples;
float elapsed = 0.0f;
bool  done    = false;

// Warm-up covers terrain streaming, shader/material compile and cache fill.
// Anything measured inside it is startup cost, not steady-state rendering.
const float WARMUP   = 20.0f;
const float DURATION = 60.0f;

void main()
{
    log("BENCH|harness loaded; warmup=" + formatFloat(WARMUP, "", 0, 1)
        + "s duration=" + formatFloat(DURATION, "", 0, 1) + "s");
}

void frameStep(float dt)
{
    if (done) return;

    elapsed += dt;
    if (elapsed < WARMUP) return;

    // dt is seconds; store milliseconds.
    samples.insertLast(dt * 1000.0f);

    if (elapsed >= WARMUP + DURATION)
    {
        done = true;
        report();
        game.quitGame();
    }
}

void report()
{
    int n = int(samples.length());
    if (n == 0)
    {
        log("BENCH|ERROR no samples collected");
        return;
    }

    samples.sortAsc();

    // Upper median: for even n this is the higher of the two central samples
    // rather than their mean. With n in the tens of thousands the two are
    // adjacent order statistics and the difference is far below run-to-run
    // noise, so it is left as-is - and the shipped benchmark data was produced
    // by exactly this code.
    float median = samples[n / 2];

    // 1%-low: mean of the slowest 1% of frames (the tail that is actually felt).
    int k = n / 100;
    if (k < 1) k = 1;
    float sum = 0.0f;
    for (int i = n - k; i < n; i++)
        sum += samples[i];
    float low1 = sum / float(k);

    float best  = samples[0];
    float worst = samples[n - 1];

    log("BENCH|RESULT"
        + "|frames="      + formatInt(n, "", 0)
        + "|median_ms="   + formatFloat(median, "", 0, 3)
        + "|low1pct_ms="  + formatFloat(low1,   "", 0, 3)
        + "|best_ms="     + formatFloat(best,   "", 0, 3)
        + "|worst_ms="    + formatFloat(worst,  "", 0, 3)
        + "|median_fps="  + formatFloat(1000.0f / median, "", 0, 2)
        + "|avgfps_game=" + formatFloat(game.getAvgFPS(), "", 0, 2));
}
