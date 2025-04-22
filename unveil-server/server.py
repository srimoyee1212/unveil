from flask import Flask, request, jsonify
from flask_cors import CORS
from groq import Groq
import os
import tempfile
import cv2
import base64
import traceback

app = Flask(__name__)
CORS(app)

client = Groq(api_key=os.getenv("GROQ_API_KEY"))

@app.route("/chat", methods=["POST"])
def chat():
    try:
        data = request.get_json()
        context = data.get("context", "")
        question = data.get("question", "")

        if not context or not question:
            return jsonify({"response": "⚠️ Missing context or question"}), 400

        full_prompt = f"You are an expert tour guide. Based on the context below, answer the user's question.\n\nContext:\n{context}\n\nQuestion:\n{question}"

        response = client.chat.completions.create(
            model="meta-llama/llama-4-scout-17b-16e-instruct",
            messages=[{"role": "user", "content": full_prompt}],
            temperature=0.7,
            max_tokens=512
        )

        return jsonify({"response": response.choices[0].message.content})

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"response": f"❌ Error: {str(e)}"}), 500


@app.route("/analyze", methods=["POST"])
def analyze_image():
    print("✅ /analyze endpoint hit")

    try:
        data = request.get_json()
        print("📥 Incoming JSON:", data)

        image_data_url = data.get("image_base64")
        location = data.get("location", "")

        if not image_data_url:
            return jsonify({"response": "⚠️ Missing image_base64 field"}), 400

        prompt = (
            "Describe the image in detail. "
            "It may depict murals, public art, architecture, sculptures, cultural landmarks, or anything visually interesting found in urban or rural areas in the United States. "
            f"If helpful, consider the following approximate location: {location}"
        )

        response = client.chat.completions.create(
            model="meta-llama/llama-4-scout-17b-16e-instruct",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": image_data_url
                            },
                        },
                    ],
                }
            ],
            temperature=1,
            max_tokens=1024,
            top_p=1,
            stream=False,
        )

        output = response.choices[0].message.content
        print("✅ Model Output:", output)
        return jsonify({"response": output})

    except Exception as e:
        traceback.print_exc()
        return jsonify({"response": f"❌ Error: {str(e)}"}), 500


@app.route("/analyze_video", methods=["POST"])
def analyze_video():
    print("🎥 /analyze_video endpoint hit")

    try:
        if 'video' not in request.files:
            return jsonify({"error": "No video uploaded"}), 400

        video_file = request.files['video']
        location = request.form.get('location', '')

        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp_video:
            video_file.save(tmp_video.name)
            print(f"📂 Saved video to {tmp_video.name}")
            video_path = tmp_video.name

        # Extract frames from video every N seconds
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_interval = int(fps * 2)  # every 2 seconds
        frame_descriptions = []

        frame_idx = 0
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
            if frame_idx % frame_interval == 0:
                _, buffer = cv2.imencode(".jpg", frame)
                jpg_as_text = base64.b64encode(buffer).decode("utf-8")
                image_data_url = f"data:image/jpeg;base64,{jpg_as_text}"

                prompt = (f"This is a frame from a video taken in the United States. "
                         f"It may depict murals, public art, architecture, landmarks, or notable scenes. "
                         f"Provide a detailed visual description. Location: {location}")
                response = client.chat.completions.create(
                    model="meta-llama/llama-4-scout-17b-16e-instruct",
                    messages=[
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": prompt},
                                {
                                    "type": "image_url",
                                    "image_url": {"url": image_data_url},
                                },
                            ],
                        }
                    ],
                    temperature=1,
                    max_tokens=512,
                    top_p=1,
                    stream=False,
                )
                desc = response.choices[0].message.content
                print(f"🖼️ Frame {frame_idx}: {desc}")
                frame_descriptions.append(desc)

            frame_idx += 1

        cap.release()

        # Combine descriptions and summarize
        combined_text = "\n".join(frame_descriptions)
        final_summary_prompt = (
            f"These are descriptions from different frames of a video taken somewhere in the United States. "
            f"Generate a cohesive summary describing what the entire video depicts, especially in terms of public art, landmarks, people, or scenery:\n{combined_text}"
        )

        summary_response = client.chat.completions.create(
            model="meta-llama/llama-4-scout-17b-16e-instruct",
            messages=[{"role": "user", "content": final_summary_prompt}],
            temperature=0.9,
            max_tokens=1024,
            top_p=1,
            stream=False,
        )

        summary = summary_response.choices[0].message.content
        print("📘 Final Video Summary:", summary)
        return jsonify({"summary": summary})

    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": f"❌ Error: {str(e)}"}), 500


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5051)
