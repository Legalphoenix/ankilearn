import SwiftUI

struct MnemonicsView: View {
    @State private var instructions: String = "You are a mnemonic creating agent. Your only role is to respond by creating a mnemonic that the user can use to aid in their recall of the target word. The target word has been provided to you."
    @State private var prompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mnemonics")
                .font(.title2.bold())

            Text("Instructions")
            TextEditor(text: $instructions)
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

            Text("Text Prompt")
            TextField("Enter your text here", text: $prompt)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Spacer()
        }
        .padding()
    }
}
