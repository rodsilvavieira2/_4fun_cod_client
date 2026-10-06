# Adapter nativo (C++) — build standalone de validação (M1).
# NÃO é incluído no build Flutter ainda (Fase 3 faz o wiring via plugin).
# Uso: cmake -S . -B build && cmake --build build (apenas checa sintaxe
# da ABI + stubs; o LiveKit C++ entra como dependência na Fase 3).
cmake_minimum_required(VERSION 3.16)
project(fourfun_media_adapter CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_library(fourfun_media_adapter STATIC
  src/livekit_adapter.cc
  src/apm_adapter.cc
  src/video_texture_adapter.cc
)
target_include_directories(fourfun_media_adapter PUBLIC include)
