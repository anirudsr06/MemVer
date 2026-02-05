<div class="title-block" style="text-align: center;" align="center">

[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![pipeline status](https://gitlab.com/shaktiproject/cores/c-class/badges/master/pipeline.svg)](https://gitlab.com/shaktiproject/cores/c-class/commits/master)
# C-Class Core Generator
</div>

## What is C-Class 

C-Class is a member of the [SHAKTI](https://shakti.org.in) family of processors.
It is an extremely configurable and commercial-grade 5-stage in-order core supporting the standard
RV64GCSUN ISA extensions. The core generator in this repository is capable of configuring the core
to generate a wide variety of design instances from the same high-level source code. The design instances
can serve domains ranging from embedded systems, motor-control, IoT, storage, industrial applications
all the way to low-cost high-performance linux based applications such as networking, gateways etc.

There have been multiple successful silicon [prototypes](http://shakti.org.in/tapeout.html)
of the different instances of the C-class thus proving its versatility. The extreme parameterization
of the design in conjunction with using an HLS like Bluespec, it makes it easy to add new features
and design points on a continual basis.

## Why Bluespec
The entire core is implemented in [Bluespec System Verilog (BSV)](https://github.com/BSVLang/Main), 
an open-source high-level hardware description language. Apart from guaranteeing synthesizable
circuits, BSV also gives you a high-level abstraction, like going from assembly [level programming] 
to C. You don’t do the dirty work, the compiler does all the work for you. It enables users to work 
at a much higher level thereby increasing throughput. 

The language is now supported by an open-source Bluespec compiler, which can generate synthesizable
verilog compatible for FPGA and ASIC targets.

## License
All of the source code available in this repository is under the BSD license. 
Please refer to LICENSE.iitm for more details.

## Commercial Adoption
The following industrial partners have adopted SHAKTI for commercialization purposes and provide
continous support in maintaining and supporting this repository.

1. InCore Semiconductors Pvt. Ltd.
2. Silint Consulting Pvt. Ltd.

## [Get Started](https://c-class.readthedocs.io/)
