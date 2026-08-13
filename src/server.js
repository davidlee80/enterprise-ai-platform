import express from "express";
import { v4 as uuid } from "uuid";
import { generatePoster } from "./pipeline.js";

const app = express();
const jobs = new Map();

app.use(express.json({
  limit: "1mb"
}));

app.use(
  "/results",
  express.static("output", {
    fallthrough: false
  })
);

app.post("/api/v1/posters", async (request, response) => {
  const jobId = uuid();

  jobs.set(jobId, {
    jobId,
    status: "queued",
    createdAt: new Date().toISOString()
  });

  response.status(202).json({
    jobId,
    status: "queued",
    statusUrl: `/api/v1/posters/${jobId}`
  });

  setImmediate(async () => {
    try {
      jobs.set(jobId, {
        ...jobs.get(jobId),
        status: "generating"
      });

      const result = await generatePoster({
        jobId,
        request: request.body
      });

      jobs.set(jobId, {
        jobId,
        status: "completed",
        imageUrl: `/results/${jobId}/poster.png`,
        htmlUrl: `/results/${jobId}/poster.html`,
        manifestUrl: `/results/${jobId}/manifest.json`,
        quality: result.quality
      });
    } catch (error) {
      jobs.set(jobId, {
        jobId,
        status: "failed",
        error: error.message
      });
    }
  });
});

app.get("/api/v1/posters/:jobId", (request, response) => {
  const job = jobs.get(request.params.jobId);

  if (!job) {
    return response.status(404).json({
      message: "任务不存在"
    });
  }

  response.json(job);
});

app.listen(3000, () => {
  console.log("Poster API: http://localhost:3000");
});