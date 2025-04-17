from flask import Flask, request, jsonify
from flask_cors import CORS
from groq import Groq
import os

app = Flask(__name__)
CORS(app)

client = Groq(api_key=os.getenv("GROQ_API_KEY"))

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
            "It might be a mural, sculpture, street art, landmark, or something unique in Austin, Texas. "
            f"Approximate location: {location}"
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
                                "url": image_data_url  # 🧠 key line — using data:image/jpeg;base64,...
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
        import traceback
        traceback.print_exc()
        return jsonify({"response": f"❌ Error: {str(e)}"}), 500


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5051)
