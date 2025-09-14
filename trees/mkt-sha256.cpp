// Implementation of a merkle tree (not sparse) on c++
// with arity 2 with some basic functions using sha256 hashing

#include<openssl/sha.h>
#include <iostream>
#include <string> 
#include <vector>

using namespace std;

// Function to compute sha256 of a string
string sha256(string input){
  unsigned char hash[SHA256_DIGEST_LENGTH];

  SHA256(reinterpret_cast<const unsigned char*>(input.c_str()), input.size(), hash);

  char buf[2*SHA256_DIGEST_LENGTH+1];
  for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
      sprintf(buf + (i*2), "%02x", hash[i]);
  buf[2*SHA256_DIGEST_LENGTH] = 0;
  return string(buf);
}

// Linked list to construct tree
struct bNode{
  string hash;
  bNode* parent;
  bNode* sibling;

  bNode(const string& to_hash) : hash(to_hash), parent(nullptr), sibling(nullptr) {}
};

bNode* buildMerkleTree(vector<string> data_block){
  vector<bNode*> currentLevel;

  for (const auto block : data_block ){
    currentLevel.push_back(new bNode(sha256(block)));
  }

  if (currentLevel.size()%2 == 1){
    currentLevel.push_back(new bNode(currentLevel.back() -> hash));
  }

  while (currentLevel.size() > 1) {
    vector<bNode*> nextLevel;

    for (int i =0; i<currentLevel.size(); i=i+2){
      bNode* left = currentLevel[i];
      bNode* right = currentLevel[i+1];

      string parentHash = sha256(left -> hash + right -> hash);
      bNode* parentNode = new bNode(parentHash);

      left -> parent = parentNode;
      right -> parent = parentNode;
      left -> sibling = right;
      right -> sibling = left;
      nextLevel.push_back(parentNode);

    }

    if (nextLevel.size()% 2 == 1 && nextLevel.size() > 1){
      nextLevel.push_back(new bNode(nextLevel.back() -> hash));
    }

    currentLevel = move(nextLevel);
  }

  return currentLevel.front();
}


int main (){
  vector<string> data_block = { "block", "block2", "block3", "block4"};

  bNode* root = buildMerkleTree(data_block);

  cout << "Merkle Root: " << root-> hash << endl;
  return 0;
}

