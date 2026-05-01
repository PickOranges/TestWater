# FFT Ocean Rendering System

## Overview
Implemented a real-time ocean rendering system using FFT-based wave simulation, focusing on large-scale water behavior and physically-based shading.

The project explores how to translate mathematical wave models into efficient real-time rendering on GPU.

## Tech Stack
- C++
- Compute Shader / GPU
- FFT (Fast Fourier Transform)
- HLSL & ShaderLab

## My Contributions

- Implemented FFT-based wave simulation to generate large-scale ocean surface using frequency-domain techniques

- Developed GPU-based height map and normal calculation using compute shaders

- Implemented physically-based water shading, including Fresnel reflection for view-dependent lighting

- Optimized performance by moving heavy computation from CPU to GPU(dynamic tessellation and height map calculation via compute shader)

## Technical Highlights

- Efficient generation of realistic ocean waves using FFT

- Real-time shading with view-dependent reflection (Fresnel effect)

- GPU acceleration for scalable and high-performance rendering

## Demo

A demo video or build can be provided upon request.
