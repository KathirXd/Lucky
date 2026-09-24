# 🧠 Lucky — Local AI Personal Assistant

> A private, locally running AI personal assistant powered by Qwen3 and llama.cpp, with persistent memory, PC awareness, and controlled filesystem tools.

---

## ✨ About

**Lucky** is a local AI personal assistant built as part of **XD 2.0**.

Unlike cloud-based AI assistants, Lucky is designed to run locally on your own Windows PC using a local LLM through **llama.cpp**.

The project focuses on:

- 🔒 Privacy-first local AI
- 🧠 Persistent personal memory
- 💻 PC/system awareness
- 📁 Controlled filesystem access
- ⚡ NVIDIA GPU acceleration
- 🛠️ PowerShell-based automation

---

## 🚀 Features

- 🧠 **Persistent Memory**
  - `/remember`
  - `/memory`
  - `/forget`

- 🤖 **Local AI**
  - Runs Qwen3 locally using GGUF
  - Powered by llama.cpp
  - No cloud API required

- ⚡ **GPU Acceleration**
  - NVIDIA CUDA support
  - GPU-accelerated inference through llama.cpp

- 💻 **PC Awareness**
  - CPU information
  - RAM information
  - GPU information
  - Storage information
  - System status

- 📁 **File Tools**
  - Directory listing
  - File searching
  - Text file reading
  - File information
  - Read-only filesystem access

- 🕐 **Live Context**
  - Current date and time
  - Live PC information when required

- 🔐 **Privacy**
  - Personal memory remains local
  - Personal personality configuration remains local
  - Sensitive files are excluded from GitHub

---

## 🏗️ Architecture

```text
                         ┌─────────────────┐
                         │      User       │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │      Lucky      │
                         │   PowerShell    │
                         └────────┬────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ▼                   ▼                   ▼
       ┌─────────────┐     ┌─────────────┐    ┌─────────────┐
       │   Memory    │     │  PC Status  │    │ File Tools  │
       │ memory.json │     │ pc_status   │    │  Read-only  │
       └─────────────┘     └─────────────┘    └─────────────┘
              │                   │                   │
              └───────────────────┼───────────────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │    llama.cpp    │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │     Qwen3       │
                         │   Local Model   │
                         └─────────────────┘


---

## 🛠️ Tech Stack

| Component        | Technology  |
| ---------------- | ----------- |
| AI Model         | Qwen3       |
| Model Format     | GGUF        |
| AI Runtime       | llama.cpp   |
| Controller       | PowerShell  |
| Memory           | JSON        |
| GPU Acceleration | NVIDIA CUDA |
| Platform         | Windows     |

---

## 📂 Project Structure

```text
Lucky/
│
├── lucky.ps1
├── start.ps1
├── file_tools.ps1
├── pc_status.ps1
│
├── memory.example.json
├── personality.example.txt
├── .gitignore
├── README.md
│
└── llama/
    └── Local llama.cpp runtime
```

### Main Files

| File                      | Description                                 |
| ------------------------- | ------------------------------------------- |
| `lucky.ps1`               | Main Lucky controller                       |
| `start.ps1`               | Starts Lucky and prepares the system prompt |
| `file_tools.ps1`          | Read-only filesystem tools                  |
| `pc_status.ps1`           | Retrieves PC/system information             |
| `memory.example.json`     | Example memory structure                    |
| `personality.example.txt` | Example personality configuration           |
| `.gitignore`              | Protects private/generated files            |

---

# 💾 Requirements

### Hardware

Recommended:

* Windows 10/11 64-bit
* 8 GB RAM or more
* NVIDIA GPU with CUDA support for GPU acceleration
* Modern multi-core CPU
* Sufficient storage for the model and llama.cpp runtime

### Software

* Windows PowerShell
* Git
* NVIDIA GPU driver
* CUDA-compatible llama.cpp build
* Compatible GGUF model

---

# 📥 Installation

## 1. Clone the Repository

```powershell
git clone https://github.com/KathirXd/Lucky.git
cd Lucky
```

## 2. Install llama.cpp

Download a Windows build of **llama.cpp** with CUDA support.

Place the required runtime files inside:

```text
Lucky\llama\
```

> Large llama.cpp/CUDA binaries are intentionally not included in this repository.

## 3. Download a GGUF Model

Lucky is designed to work with compatible GGUF models.

The development setup uses:

```text
Qwen3-4B
Q4_K_M
```

Model files are not included in this repository because of their size.

## 4. Create Your Personality File

```powershell
Copy-Item personality.example.txt personality.txt
```

Edit `personality.txt` to customize Lucky's behavior.

## 5. Create Your Memory File

```powershell
Copy-Item memory.example.json memory.json
```

Your personal `memory.json` is intentionally excluded from GitHub.

## 6. Start Lucky

```powershell
.\start.ps1
```

---

# 🧠 Memory System

Lucky supports persistent memory through a local JSON file.

### Remember

```text
/remember I prefer dark mode
```

### View Memory

```text
/memory
```

### Forget

```text
/forget I prefer dark mode
```

### Exit

```text
/exit
```

Memory is stored locally in:

```text
memory.json
```

---

# 💻 PC Awareness

Lucky can retrieve information about the computer using:

```text
pc_status.ps1
```

This allows the assistant to work with current system information.

---

# 📁 File Tools

Lucky includes controlled, read-only filesystem tools.

The tools can:

* List directories
* Search files
* Read text files
* Inspect file information

Filesystem access is intentionally restricted to configured locations.

---

# 🔐 Privacy & Security

Lucky is designed to keep personal information local.

The following files are intentionally excluded from the public repository:

```text
memory.json
personality.txt
active_system_prompt.txt
active_request_prompt.txt
```

Example files are provided instead:

```text
memory.example.json
personality.example.txt
```

### Never commit:

```text
API keys
Passwords
Access tokens
Private keys
Personal memory
Private configuration
```

---

# 🚫 Large Files

The repository does not include:

* CUDA runtime ZIP files
* Large CUDA DLLs
* GGUF model files
* Personal memory
* Personal configuration

This keeps the GitHub repository lightweight.

---

# ⚙️ Configuration

Lucky's runtime can be configured through the PowerShell scripts.

Typical configuration includes:

```text
Model
Context size
GPU layers
Reasoning mode
System prompt
Memory
Tool locations
```

---

# 📊 Project Status

| Feature                 | Status |
| ----------------------- | :----: |
| Local LLM               |    ✅   |
| Qwen3                   |    ✅   |
| llama.cpp               |    ✅   |
| NVIDIA GPU acceleration |    ✅   |
| Persistent memory       |    ✅   |
| `/remember`             |    ✅   |
| `/memory`               |    ✅   |
| `/forget`               |    ✅   |
| PC status               |    ✅   |
| File tools              |    ✅   |
| Read-only filesystem    |    ✅   |
| Live time context       |    ✅   |
| GitHub repository       |    ✅   |
| GUI                     |   🚧   |
| Voice input             |   🚧   |
| Voice output            |   🚧   |
| Web search              |   🚧   |

---

# 🗺️ Roadmap

### Core Assistant

* [x] Local LLM
* [x] llama.cpp integration
* [x] GPU acceleration
* [x] PowerShell controller
* [x] Persistent memory

### System Integration

* [x] PC monitoring
* [x] File tools
* [x] Live time
* [x] Controlled filesystem access

### Future

* [ ] GUI
* [ ] Voice input
* [ ] Voice output
* [ ] Web search
* [ ] Application automation
* [ ] Plugin/tool system
* [ ] Multiple local models
* [ ] Advanced agent capabilities

---

# 🤝 Contributing

Contributions, suggestions, and improvements are welcome.

```bash
git clone https://github.com/KathirXd/Lucky.git
cd Lucky
git checkout -b feature/my-feature
```

Make your changes and submit a pull request.

---

# 👨‍💻 Author

**Kathiravan**

GitHub: [@KathirXd](https://github.com/KathirXd)

---

# ⭐ About Lucky

Lucky started as a personal local AI assistant and evolved into a system-aware assistant with:

* Persistent memory
* Local LLM inference
* PC awareness
* Controlled filesystem tools
* GPU acceleration

### Built with

**Qwen3 + llama.cpp + PowerShell + NVIDIA CUDA**

---

## ⭐ Support

If you find Lucky interesting, consider giving the repository a ⭐ on GitHub.

