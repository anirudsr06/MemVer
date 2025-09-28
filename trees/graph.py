import math
import matplotlib.pyplot as plt
import numpy as np
import matplotlib.colors as mcolors


TOTAL_MEMORY_BYTES = 256 * 1024 * 1024  # 256 MB
HASH_SIZE_BYTES = 32  #SHA-256


def calculate_metrics_and_cost(total_memory, chunk_size, arity):    

    num_leaves = total_memory / chunk_size

    # Calculate Tree Height
    tree_height = math.ceil(math.log(num_leaves, arity))
    
    # Calculate Proof Size
    proof_size = tree_height * (arity-1) * HASH_SIZE_BYTES

    # Calculate Tree Size (Memory Overhead)
    num_internal_nodes = 0

    current_level_nodes = num_leaves

    while current_level_nodes > 1:
        current_level_nodes = math.ceil(current_level_nodes / arity)
        num_internal_nodes += current_level_nodes

    tree_size = num_internal_nodes * HASH_SIZE_BYTES

    # Calculate Total Hashing Data (Update Cost)
    total_hashing_data = chunk_size + proof_size

    
    return tree_height, proof_size, tree_size, total_hashing_data

# Chunk sizes from 32B to 16KB

chunk_sizes = [2**i for i in range(5, 15)]

# Arities from 2 to 32

arities = [2, 4, 8, 16, 32]


# --- Data Generation ---

height_matrix = np.zeros((len(chunk_sizes), len(arities)))

proof_size_matrix = np.zeros((len(chunk_sizes), len(arities)))

tree_size_matrix = np.zeros((len(chunk_sizes), len(arities)))

update_cost_matrix = np.zeros((len(chunk_sizes), len(arities)))


for i, cs in enumerate(chunk_sizes):

    for j, a in enumerate(arities):

        height, proof_size, tree_size, total_hashing_data = calculate_metrics_and_cost(TOTAL_MEMORY_BYTES, cs, a)

        height_matrix[i, j] = height

        proof_size_matrix[i, j] = proof_size / 1024  # Convert to KB

        tree_size_matrix[i, j] = tree_size / (1024 * 1024)  # Convert to MB

        update_cost_matrix[i, j] = total_hashing_data / 1024  # Convert to KB


# --- Plotting Heatmaps ---

fig, axes = plt.subplots(1, 4, figsize=(22, 6), sharey=True)


# Heatmap 1: Tree Height

im1 = axes[0].imshow(height_matrix, cmap='YlGnBu', origin='lower', aspect='auto')

axes[0].set_title('Merkle Tree Height')

axes[0].set_xlabel('Arity')

axes[0].set_ylabel('Chunk Size')

axes[0].set_xticks(np.arange(len(arities)))

axes[0].set_xticklabels(arities)

axes[0].set_yticks(np.arange(len(chunk_sizes)))

axes[0].set_yticklabels([f'{cs}' if cs < 1024 else f'{cs/1024:.0f}K' for cs in chunk_sizes])

fig.colorbar(im1, ax=axes[0], label='Levels')


# Heatmap 2: Proof Size (KB)

im2 = axes[1].imshow(proof_size_matrix, cmap='PuRd', origin='lower', aspect='auto')

axes[1].set_title('Merkle Proof Size (KB)')

axes[1].set_xlabel('Arity')

axes[1].set_xticks(np.arange(len(arities)))

axes[1].set_xticklabels(arities)

fig.colorbar(im2, ax=axes[1], label='Size (KB)')


# Heatmap 3: Tree Size (MB) with Logarithmic Scale

im3 = axes[2].imshow(

    tree_size_matrix, 

    cmap='YlOrRd', 

    origin='lower', 

    aspect='auto',

    norm=mcolors.LogNorm(vmin=tree_size_matrix.min(), vmax=tree_size_matrix.max())

)

axes[2].set_title('Merkle Tree Overhead (MB)')

axes[2].set_xlabel('Arity')

axes[2].set_xticks(np.arange(len(arities)))

axes[2].set_xticklabels(arities)

fig.colorbar(im3, ax=axes[2], label='Size (MB)')


# Heatmap 4: Total Hashing Data (Update Cost)

im4 = axes[3].imshow(update_cost_matrix, cmap='Greens', origin='lower', aspect='auto')

axes[3].set_title('Update Cost (Total Hashing Data in KB)')

axes[3].set_xlabel('Arity')

axes[3].set_xticks(np.arange(len(arities)))

axes[3].set_xticklabels(arities)

fig.colorbar(im4, ax=axes[3], label='Size (KB)')


plt.tight_layout()

plt.show() 
