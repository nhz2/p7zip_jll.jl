# Use baremodule to shave off a few KB from the serialized `.ji` file
baremodule p7zip_jll
using Base
using Base: UUID
import JLLWrappers

JLLWrappers.@generate_main_file_header("p7zip")
JLLWrappers.@generate_main_file("p7zip", UUID("3f19e933-33d8-53b3-aaab-bd5110c3b7a0"))
end  # module p7zip_jll
